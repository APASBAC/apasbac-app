import 'dart:io';
import 'dart:typed_data';

import 'package:apasbac_app/core/services/capture_attestation.dart';
import 'package:apasbac_app/core/services/monitoring_upload_queue.dart';
import 'package:apasbac_app/core/services/storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

XFile file(String name) =>
    XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name);

CapturedFile captured(String name, String kind) => CapturedFile(
    file(name),
    CaptureProof(
        kind: kind,
        md5: '5289df737df57326fcdd22597afb1fac',
        capturedAt: '2026-11-26T12:00:00.000Z',
        signature: List.filled(64, 'a').join()));

class Recorder implements UploadNotifier {
  final events = <String>[];
  @override
  Future<void> progress(UploadJob job) async => events.add('progress');
  @override
  Future<void> waiting(UploadJob job) async => events.add('waiting');
  @override
  Future<void> stop() async => events.add('stop');
  @override
  Future<void> done(UploadJob job) async => events.add('done');
  @override
  Future<void> failed(UploadJob job) async => events.add('failed');
}

DioException offline() =>
    DioException.connectionError(requestOptions: RequestOptions(), reason: 'x');

Future<void> settle(MonitoringUploadQueue q) async {
  for (var i = 0; i < 200; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
    if (q.jobs.every((j) => j.status == UploadStatus.failed)) return;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory tmp;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tmp = Directory.systemTemp.createTempSync('uploads');
  });
  tearDown(() => tmp.deleteSync(recursive: true));

  Future<void> enqueue(MonitoringUploadQueue q, [String id = 'm1']) =>
      q.enqueue(
          monitoringId: id,
          animalName: 'Bolt',
          video: captured('video.mp4', 'video'),
          images: [for (var i = 0; i < 5; i++) captured('f$i.jpg', 'image')],
          captureToken: 'token-de-captura',
          captureKey: 'chave-teste');

  test('envia em segundo plano, registra na API e avisa ao terminar', () async {
    final uploaded = <String>[];
    List<String>? sentImages;
    String? sentToken;
    List<Map<String, dynamic>>? sentMedia;
    String? sentVideo;
    final notes = Recorder();
    String? finished;
    final q = MonitoringUploadQueue(
      directory: () async => tmp,
      notifier: notes,
      upload: (path, {required video, onProgress}) async {
        onProgress?.call(1);
        uploaded.add(path);
        return UploadedFile(
            'https://res.cloudinary.com/x/${path.split('/').last}', null);
      },
      finish: (id, video, images, token, media) async {
        sentVideo = video;
        sentImages = images;
        sentToken = token;
        sentMedia = media;
      },
    )..onFinished = (id) => finished = id;

    await enqueue(q);
    // Os arquivos já estão copiados: a pessoa pode sair da tela.
    await settle(q);
    expect(uploaded.length, 6);
    expect(sentVideo, contains('/video.'));
    expect(sentImages, hasLength(5));
    // Atestado de captura vai junto, um por URL, com a URL enviada.
    expect(sentToken, 'token-de-captura');
    expect(sentMedia, hasLength(6));
    expect(sentMedia!.first['url'], sentVideo);
    expect(sentMedia!.first['kind'], 'video');
    expect(sentMedia!.skip(1).every((m) => m['kind'] == 'image'), isTrue);
    expect(finished, 'm1');
    expect(q.jobs, isEmpty);
    expect(notes.events, containsAllInOrder(['progress', 'done', 'stop']));
    expect(Directory('${tmp.path}/monitoring_uploads/m1').existsSync(), isFalse,
        reason: 'cópias locais apagadas depois do envio');
  });

  test('sem internet espera e continua sem reenviar o que já subiu', () async {
    final calls = <String, int>{};
    var failNext = 2;
    final q = MonitoringUploadQueue(
      directory: () async => tmp,
      retryDelays: const [Duration.zero, Duration.zero, Duration.zero],
      upload: (path, {required video, onProgress}) async {
        calls[path] = (calls[path] ?? 0) + 1;
        if (video && failNext-- > 0) throw offline();
        return UploadedFile('https://res.cloudinary.com/x/1', null);
      },
      finish: (id, video, images, token, media) async {},
    );
    await enqueue(q);
    await settle(q);
    expect(q.jobs, isEmpty);
    final photoCalls = calls.entries.where((e) => !e.key.contains('/video.'));
    expect(photoCalls.every((e) => e.value == 1), isTrue,
        reason: 'fotos enviadas uma única vez');
  });

  test('erro definitivo da API fica como falha e pode tentar de novo',
      () async {
    var reject = true;
    final notes = Recorder();
    final q = MonitoringUploadQueue(
      directory: () async => tmp,
      notifier: notes,
      upload: (path, {required video, onProgress}) async =>
          const UploadedFile('https://u/1', null),
      finish: (id, video, images, token, media) async {
        if (reject) {
          throw DioException(
              requestOptions: RequestOptions(),
              response: Response(
                  requestOptions: RequestOptions(),
                  statusCode: 400,
                  data: {'message': 'Este monitoramento já foi enviado'}));
        }
      },
    );
    await enqueue(q);
    await settle(q);
    final job = q.jobFor('m1')!;
    expect(job.status, UploadStatus.failed);
    expect(job.error, contains('Este monitoramento já foi enviado'));
    expect(notes.events, contains('failed'));
    reject = false;
    await q.retry('m1');
    await settle(q);
    expect(q.jobFor('m1'), isNull);
  });

  test('envio interrompido (app fechado) é retomado na próxima abertura',
      () async {
    final blocked = MonitoringUploadQueue(
      directory: () async => tmp,
      retryDelays: const [],
      upload: (path, {required video, onProgress}) async {
        if (video) throw const FileSystemException('app encerrado');
        return UploadedFile('https://u/${path.split('/').last}', null);
      },
      finish: (id, video, images, token, media) async {},
    );
    await enqueue(blocked);
    await settle(blocked);
    // Simula o processo morto no meio: muda o estado salvo para "enviando".
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString('monitoring_upload_jobs')!;
    await prefs.setString('monitoring_upload_jobs',
        raw.replaceAll('"status":"failed"', '"status":"uploading"'));

    final uploads = <String>[];
    final reopened = MonitoringUploadQueue(
      directory: () async => tmp,
      upload: (path, {required video, onProgress}) async {
        uploads.add(path);
        return UploadedFile('https://u/v', null);
      },
      finish: (id, video, images, token, media) async {},
    );
    await reopened.resume();
    await settle(reopened);
    expect(reopened.jobs, isEmpty);
    expect(uploads.single, contains('/video.'),
        reason: 'só o vídeo faltava; fotos já enviadas não sobem de novo');
  });

  test('não aceita dois envios do mesmo monitoramento ao mesmo tempo',
      () async {
    final q = MonitoringUploadQueue(
      directory: () async => tmp,
      upload: (path, {required video, onProgress}) => Future.delayed(
          const Duration(seconds: 5), () => const UploadedFile('u', null)),
      finish: (id, video, images, token, media) async {},
    );
    await enqueue(q);
    expect(() => enqueue(q), throwsStateError);
    await q.clearAll();
  });

  test(
      'envio salvo por versão antiga (sem atestado) falha pedindo nova gravação',
      () async {
    final prefs = await SharedPreferences.getInstance();
    final dir = Directory('${tmp.path}/old')..createSync();
    final paths = [
      for (final n in ['v.mp4', 'a.jpg'])
        (File('${dir.path}/$n')..writeAsBytesSync([1])).path
    ];
    await prefs.setString('monitoring_upload_jobs',
        '[{"monitoringId":"m9","animalName":"Mel","videoPath":"${paths[0]}","imagePaths":["${paths[1]}"],"uploaded":{},"status":"queued","progress":0}]');
    var uploads = 0;
    final q = MonitoringUploadQueue(
      directory: () async => tmp,
      upload: (path, {required video, onProgress}) async {
        uploads++;
        return UploadedFile('u', null);
      },
      finish: (id, video, images, token, media) async {},
    );
    await q.resume();
    await settle(q);
    expect(uploads, 0, reason: 'nada sobe sem atestado');
    expect(q.jobFor('m9')!.status, UploadStatus.failed);
    expect(q.jobFor('m9')!.error, contains('câmera do aplicativo'));
  });

  test('com o etag do Cloudinary, o app assina a ligação arquivo → upload',
      () async {
    List<Map<String, dynamic>>? sent;
    final q = MonitoringUploadQueue(
      directory: () async => tmp,
      upload: (path, {required video, onProgress}) async => UploadedFile(
          'https://u/${path.split('/').last}',
          '9e107d9d372bb6826bd81d3542a419d6'),
      finish: (id, video, images, token, media) async => sent = media,
    );
    await q.enqueue(
        monitoringId: 'm1',
        animalName: 'Bolt',
        video: captured('video.mp4', 'video'),
        images: [for (var i = 0; i < 5; i++) captured('f$i.jpg', 'image')],
        captureToken: 'token-de-captura',
        captureKey: 'chave-teste');
    await settle(q);
    expect(sent, hasLength(6));
    final video = sent!.first;
    expect(video['uploadEtag'], '9e107d9d372bb6826bd81d3542a419d6');
    expect(
        video['uploadSignature'],
        uploadSignature('chave-teste', video['md5'] as String,
            '9e107d9d372bb6826bd81d3542a419d6', video['url'] as String, 'm1'));
  });
}
