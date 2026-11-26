import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/friendly_error.dart';
import 'capture_attestation.dart';
import 'monitoring_service.dart';
import 'storage_service.dart';

enum UploadStatus { queued, uploading, waitingNetwork, failed }

/// Um envio de monitoramento na fila (persistido no aparelho).
class UploadJob {
  final String monitoringId;
  final String animalName;
  final String videoPath;
  final List<String> imagePaths;

  /// Caminho local → URL já enviada (não reenvia ao retomar).
  final Map<String, String> uploaded;

  /// Sessão de captura e atestado de cada arquivo (gravado pela câmera do app).
  final String? captureToken;
  final Map<String, CaptureProof> proofs;
  UploadStatus status;
  double progress;
  String? error;

  UploadJob({
    required this.monitoringId,
    required this.animalName,
    required this.videoPath,
    required this.imagePaths,
    Map<String, String>? uploaded,
    this.captureToken,
    Map<String, CaptureProof>? proofs,
    this.status = UploadStatus.queued,
    this.progress = 0,
    this.error,
  })  : uploaded = uploaded ?? {},
        proofs = proofs ?? {};

  /// Envio criado por versão antiga do app (sem atestado): não é mais aceito.
  bool get attested =>
      captureToken != null && files.every((f) => proofs.containsKey(f));

  List<String> get files => [...imagePaths, videoPath];
  bool get active => status != UploadStatus.failed;

  Map<String, dynamic> toJson() => {
        'monitoringId': monitoringId,
        'animalName': animalName,
        'videoPath': videoPath,
        'imagePaths': imagePaths,
        'uploaded': uploaded,
        'captureToken': captureToken,
        'proofs': proofs.map((k, v) => MapEntry(k, v.toJson())),
        'status': status.name,
        'progress': progress,
        'error': error,
      };

  factory UploadJob.fromJson(Map<String, dynamic> j) => UploadJob(
        monitoringId: j['monitoringId'] as String,
        animalName: (j['animalName'] as String?) ?? '',
        videoPath: j['videoPath'] as String,
        imagePaths: List<String>.from(j['imagePaths'] as List),
        uploaded: Map<String, String>.from((j['uploaded'] as Map?) ?? {}),
        captureToken: j['captureToken'] as String?,
        proofs: ((j['proofs'] as Map?) ?? {}).map((k, v) => MapEntry(
            k as String,
            CaptureProof.fromJson(Map<String, dynamic>.from(v as Map)))),
        status: UploadStatus.values.firstWhere((s) => s.name == j['status'],
            orElse: () => UploadStatus.queued),
        progress: (j['progress'] as num?)?.toDouble() ?? 0,
        error: j['error'] as String?,
      );
}

/// Avisos do envio no Android (serviço em primeiro plano + notificações).
abstract class UploadNotifier {
  Future<void> progress(UploadJob job);
  Future<void> waiting(UploadJob job);
  Future<void> stop();
  Future<void> done(UploadJob job);
  Future<void> failed(UploadJob job);
}

class SilentUploadNotifier implements UploadNotifier {
  const SilentUploadNotifier();
  @override
  Future<void> progress(UploadJob job) async {}
  @override
  Future<void> waiting(UploadJob job) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> done(UploadJob job) async {}
  @override
  Future<void> failed(UploadJob job) async {}
}

typedef UploadFile = Future<String> Function(String path,
    {required bool video, void Function(double)? onProgress});
typedef FinishSubmit = Future<void> Function(
    String monitoringId,
    String videoUrl,
    List<String> imageUrls,
    String captureToken,
    List<Map<String, dynamic>> media);

/// Fila de envio dos monitoramentos.
///
/// O tutor toca em "Enviar" e pode sair do aplicativo: os arquivos são copiados
/// para a pasta do app, o envio é salvo no aparelho e segue em segundo plano
/// (serviço em primeiro plano com notificação de progresso). Sem internet, o
/// app espera e tenta de novo; se for encerrado, retoma na próxima abertura
/// sem reenviar os arquivos que já subiram.
class MonitoringUploadQueue extends ChangeNotifier {
  MonitoringUploadQueue({
    UploadFile? upload,
    FinishSubmit? finish,
    Future<Directory> Function()? directory,
    UploadNotifier notifier = const SilentUploadNotifier(),
    this.retryDelays = const [
      Duration(seconds: 5),
      Duration(seconds: 15),
      Duration(seconds: 30),
      Duration(minutes: 1),
      Duration(minutes: 2),
      Duration(minutes: 5),
    ],
  })  : _upload = upload ?? _defaultUpload,
        _finish = finish ?? _defaultFinish,
        _directory = directory ?? _appFilesDir,
        _notifier = notifier;

  static MonitoringUploadQueue instance = MonitoringUploadQueue();

  static const _prefsKey = 'monitoring_upload_jobs';
  final UploadFile _upload;
  final FinishSubmit _finish;
  final Future<Directory> Function() _directory;
  UploadNotifier _notifier;
  final List<Duration> retryDelays;

  final List<UploadJob> _jobs = [];
  bool _loaded = false;
  bool _running = false;
  bool _enabled = true;

  /// Chamado quando um monitoramento termina de ser enviado.
  void Function(String monitoringId)? onFinished;

  set notifier(UploadNotifier value) => _notifier = value;

  List<UploadJob> get jobs => List.unmodifiable(_jobs);
  UploadJob? jobFor(String monitoringId) {
    for (final j in _jobs) {
      if (j.monitoringId == monitoringId) return j;
    }
    return null;
  }

  /// Pasta privada do app, pedida ao código nativo do próprio app. O
  /// path_provider usa JNI e falhava no APK de release (classe removida pelo R8).
  static Future<Directory> _appFilesDir() async {
    try {
      final path = await const MethodChannel('org.apasbac/app_update')
          .invokeMethod<String>('filesDir');
      if (path != null && path.isNotEmpty) return Directory(path);
    } catch (_) {}
    return getApplicationSupportDirectory();
  }

  static Future<String> _defaultUpload(String path,
      {required bool video, void Function(double)? onProgress}) {
    return StorageService().upload(XFile(path),
        folder: video ? 'monitoring/videos' : 'monitoring/images',
        resourceType: video ? 'video' : 'image', onProgress: (sent, total) {
      if (total > 0) onProgress?.call(sent / total);
    });
  }

  static Future<void> _defaultFinish(
          String id,
          String videoUrl,
          List<String> imageUrls,
          String captureToken,
          List<Map<String, dynamic>> media) =>
      MonitoringService().finishSubmit(
          monitoringId: id,
          videoUrl: videoUrl,
          imageUrls: imageUrls,
          captureToken: captureToken,
          media: media);

  Future<void> _load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null) return;
      for (final j in jsonDecode(raw) as List) {
        final job = UploadJob.fromJson(Map<String, dynamic>.from(j as Map));
        // Interrompido pelo sistema: volta para a fila.
        if (job.status != UploadStatus.failed) job.status = UploadStatus.queued;
        _jobs.add(job);
      }
    } catch (e) {
      debugPrint('[UploadQueue] fila ilegível: $e');
    }
  }

  Future<void> _save() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
        _prefsKey, jsonEncode(_jobs.map((j) => j.toJson()).toList()));
  }

  /// Coloca o envio na fila e começa a enviar. Retorna quando os arquivos já
  /// estão copiados e salvos (a pessoa já pode sair do app).
  Future<void> enqueue({
    required String monitoringId,
    required String animalName,
    required CapturedFile video,
    required List<CapturedFile> images,
    required String captureToken,
  }) async {
    await _load();
    final existing = jobFor(monitoringId);
    if (existing != null && existing.active) {
      throw StateError('Este monitoramento já está sendo enviado.');
    }
    if (existing != null) await _discard(existing);
    for (final f in [...images, video]) {
      if (await f.file.length() == 0) throw ArgumentError('Arquivo vazio.');
    }
    final proofs = <String, CaptureProof>{};
    final base = await _directory();
    final dir = Directory(
        '${base.path}/monitoring_uploads/${monitoringId.replaceAll(RegExp(r'[^\w-]'), '_')}');
    if (dir.existsSync()) dir.deleteSync(recursive: true);
    dir.createSync(recursive: true);
    Future<String> keep(CapturedFile c, String name) async {
      final f = c.file;
      final source = f.name.isNotEmpty ? f.name : f.path;
      final ext = source.contains('.') ? source.split('.').last : 'bin';
      final target = '${dir.path}/$name.$ext';
      await f.saveTo(target);
      proofs[target] = c.proof;
      return target;
    }

    final imagePaths = <String>[];
    for (var i = 0; i < images.length; i++) {
      imagePaths.add(await keep(images[i], 'foto_${i + 1}'));
    }
    final job = UploadJob(
      monitoringId: monitoringId,
      animalName: animalName,
      videoPath: await keep(video, 'video'),
      imagePaths: imagePaths,
      captureToken: captureToken,
      proofs: proofs,
    );
    _jobs.add(job);
    await _save();
    notifyListeners();
    unawaited(_process());
  }

  /// Retoma envios pendentes (ao abrir o app ou após login).
  Future<void> resume() async {
    _enabled = true;
    await _load();
    notifyListeners();
    unawaited(_process());
  }

  Future<void> retry(String monitoringId) async {
    final job = jobFor(monitoringId);
    if (job == null || job.active) return;
    job
      ..status = UploadStatus.queued
      ..error = null;
    await _save();
    notifyListeners();
    unawaited(_process());
  }

  /// Desiste do envio e apaga as cópias locais.
  Future<void> cancel(String monitoringId) async {
    final job = jobFor(monitoringId);
    if (job == null || job.status == UploadStatus.uploading) return;
    await _discard(job);
    notifyListeners();
  }

  /// Ao sair da conta: os envios pertencem a quem estava logado.
  Future<void> clearAll() async {
    _enabled = false;
    await _load();
    for (final job in List.of(_jobs)) {
      await _discard(job);
    }
    await _notifier.stop();
    notifyListeners();
  }

  Future<void> _discard(UploadJob job) async {
    _jobs.remove(job);
    try {
      final parent = File(job.videoPath).parent;
      if (parent.existsSync()) parent.deleteSync(recursive: true);
    } catch (_) {}
    await _save();
  }

  static bool _isNetworkError(Object e) =>
      e is DioException &&
      (e.response == null ||
          (e.response!.statusCode ?? 0) >= 500 ||
          e.response!.statusCode == 408 ||
          e.response!.statusCode == 429);

  static String _message(Object e) => describeError(e).text;

  Future<void> _process() async {
    if (_running || !_enabled) return;
    _running = true;
    try {
      while (_enabled) {
        UploadJob? job;
        for (final j in _jobs) {
          if (j.status == UploadStatus.queued) {
            job = j;
            break;
          }
        }
        if (job == null) break;
        await _run(job);
      }
    } finally {
      _running = false;
      await _notifier.stop();
    }
  }

  Future<void> _run(UploadJob job) async {
    var attempt = 0;
    while (_enabled && _jobs.contains(job)) {
      try {
        job
          ..status = UploadStatus.uploading
          ..error = null;
        notifyListeners();
        await _notifier.progress(job);
        if (!job.attested) {
          throw StateError(
              'Grave as fotos e o vídeo de novo pela câmera do aplicativo.');
        }
        final files = job.files;
        for (var i = 0; i < files.length; i++) {
          final path = files[i];
          if (job.uploaded.containsKey(path)) continue;
          if (!File(path).existsSync()) {
            throw FileSystemException('Arquivo ausente', path);
          }
          var lastShown = -1;
          final url = await _upload(path, video: path == job.videoPath,
              onProgress: (p) {
            // Etapas: cada arquivo vale 1/(n+1); o registro final, o restante.
            job.progress = (i + p) / (files.length + 1);
            notifyListeners();
            final pct = (job.progress * 100).floor();
            if (pct != lastShown && pct % 2 == 0) {
              lastShown = pct;
              unawaited(_notifier.progress(job));
            }
          });
          job.uploaded[path] = url;
          job.progress = (i + 1) / (files.length + 1);
          await _save();
          notifyListeners();
        }
        await _finish(
          job.monitoringId,
          job.uploaded[job.videoPath]!,
          [for (final p in job.imagePaths) job.uploaded[p]!],
          job.captureToken!,
          [
            for (final p in [job.videoPath, ...job.imagePaths])
              job.proofs[p]!.forUrl(job.uploaded[p]!)
          ],
        );
        job.progress = 1;
        await _discard(job);
        notifyListeners();
        await _notifier.done(job);
        onFinished?.call(job.monitoringId);
        return;
      } catch (e) {
        debugPrint('[UploadQueue] falha no envio: $e');
        if (_isNetworkError(e) && attempt < retryDelays.length) {
          job
            ..status = UploadStatus.waitingNetwork
            ..error = _message(e);
          notifyListeners();
          await _notifier.waiting(job);
          await Future<void>.delayed(retryDelays[attempt++]);
          continue;
        }
        job
          ..status = UploadStatus.failed
          ..error = _message(e);
        await _save();
        notifyListeners();
        await _notifier.failed(job);
        return;
      }
    }
  }
}
