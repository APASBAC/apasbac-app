import 'dart:io';
import 'dart:typed_data';

import 'package:apasbac_app/core/services/monitoring_upload_queue.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';

XFile file(String name) =>
    XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name);

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
          video: file('video.mp4'),
          images: [for (var i = 0; i < 5; i++) file('f$i.jpg')]);

  test('envia em segundo plano, registra na API e avisa ao terminar', () async {
    final uploaded = <String>[];
    List<String>? sentImages;
    String? sentVideo;
    final notes = Recorder();
    String? finished;
    final q = MonitoringUploadQueue(
      directory: () async => tmp,
      notifier: notes,
      upload: (path, {required video, onProgress}) async {
        onProgress?.call(1);
        uploaded.add(path);
        return 'https://res.cloudinary.com/x/${path.split('/').last}';
      },
      finish: (id, video, images) async {
        sentVideo = video;
        sentImages = images;
      },
    )..onFinished = (id) => finished = id;

    await enqueue(q);
    // Os arquivos já estão copiados: a pessoa pode sair da tela.
    await settle(q);
    expect(uploaded.length, 6);
    expect(sentVideo, contains('/video.'));
    expect(sentImages, hasLength(5));
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
        return 'https://res.cloudinary.com/x/1';
      },
      finish: (id, video, images) async {},
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
      upload: (path, {required video, onProgress}) async => 'https://u/1',
      finish: (id, video, images) async {
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
        return 'https://u/${path.split('/').last}';
      },
      finish: (id, video, images) async {},
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
        return 'https://u/v';
      },
      finish: (id, video, images) async {},
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
      upload: (path, {required video, onProgress}) =>
          Future.delayed(const Duration(seconds: 5), () => 'u'),
      finish: (id, video, images) async {},
    );
    await enqueue(q);
    expect(() => enqueue(q), throwsStateError);
    await q.clearAll();
  });
}
