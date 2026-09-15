import 'dart:typed_data';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:apasbac_app/core/models/create_animal.dart';
import 'package:apasbac_app/core/services/animal_service.dart';
import 'package:apasbac_app/core/services/config_service.dart';
import 'package:apasbac_app/core/services/monitoring_service.dart';
import 'package:apasbac_app/core/services/storage_service.dart';
import 'package:apasbac_app/core/widgets/apasbac_logo.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_forms.dart';

Dio fakeApi(dynamic Function(RequestOptions) respond) {
  final dio = Dio(BaseOptions(baseUrl: 'https://api.example.test'));
  dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
    h.resolve(Response(requestOptions: r, statusCode: 200, data: respond(r)));
  }));
  return dio;
}

class FakeStorage extends StorageService {
  int calls = 0;
  final bool fail;
  FakeStorage({this.fail = false}) : super(api: Dio(), cloudinary: Dio());
  @override
  Future<String> upload(XFile file,
      {required String folder,
      String resourceType = 'image',
      ProgressCallback? onProgress}) async {
    calls++;
    if (fail) throw StateError('Upload falhou');
    return 'https://res.cloudinary.com/demo/$resourceType/$calls';
  }
}

XFile fixture(String name) =>
    XFile.fromData(Uint8List.fromList([1, 2, 3]), name: name);

class MissingLogoBundle extends CachingAssetBundle {
  @override
  Future<ByteData> load(String key) {
    if (key.endsWith('apasbac_logo.png')) {
      return Future.error(StateError('Logo unavailable for fallback test'));
    }
    return rootBundle.load(key);
  }
}

void main() {
  testWidgets('Logo ausente usa ícone provisório', (tester) async {
    await tester.pumpWidget(MaterialApp(home: DefaultAssetBundle(
      bundle: MissingLogoBundle(), child: const ApasbacLogo())));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.pets), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('Cadastro valida campos obrigatórios', (tester) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
        const ProviderScope(child: MaterialApp(home: AnimalCreateScreen())));
    await tester.ensureVisible(find.text('Cadastrar animal'));
    await tester.tap(find.text('Cadastrar animal'));
    await tester.pump();
    expect(find.text('Campo obrigatório'), findsNWidgets(3));
  });
  test('Animal envia JSON com URLs, lista e booleano', () async {
    final service = AnimalService(api: fakeApi((r) {
      expect(r.path, '/animals');
      expect(r.method, 'POST');
      expect(r.data['photoUrls'], ['https://example.test/photo.jpg']);
      expect(r.data['escapeTendency'], false);
      expect(r.data['vaccines'], ['V10']);
      expect(r.data['name'], 'Lua');
      return {};
    }));
    await service.createAnimal(const CreateAnimal(
        name: ' Lua ',
        description: 'Resgatada',
        breed: 'SRD',
        sex: 'FEMALE',
        size: 'MEDIUM',
        temperament: 'Dócil',
        vaccines: ['V10'],
        photoUrls: ['https://example.test/photo.jpg']));
    expect(
        () => CreateAnimal(
                name: 'Lua',
                description: 'Resgatada',
                breed: 'SRD',
                sex: 'FEMALE',
                size: 'MEDIUM',
                temperament: '',
                photoUrls: List.filled(4, 'https://example.test/p.jpg'))
            .toJson(),
        throwsArgumentError);
  });
  test('Configurações lê envelope e valida antes do PATCH', () async {
    final requests = <RequestOptions>[];
    final service = ConfigService(api: fakeApi((r) {
      requests.add(r);
      return {
        'data': [
          {'key': 'monitoring_period_value', 'value': '6'}
        ]
      };
    }));
    expect((await service.getConfigs()).single['value'], '6');
    await service.update('monitoring_period_value', ' 3 ', 'Período');
    expect(requests.last.method, 'PATCH');
    expect(requests.last.path, '/configs/monitoring_period_value');
    expect(requests.last.data['value'], '3');
    await expectLater(service.update('monitoring_period_value', '0', ''),
        throwsArgumentError);
    expect(requests.length, 2);
    expect(
        ConfigService.validate('monitoring_period_unit', 'INVALID'), isNotNull);
    expect(ConfigService.validate('apasbac_email', 'inválido'), isNotNull);
  });
  test('Upload preserva campos assinados e não envia JWT', () async {
    final api = fakeApi((r) {
      expect(r.data, {'folder': 'animals/photos', 'resource_type': 'image'});
      return {
        'data': {
          'upload_url': 'https://api.cloudinary.com/v1_1/demo/image/upload',
          'form_fields': {
            'api_key': 'key',
            'signature': 'signed',
            'timestamp': 123,
            'folder': 'animals/photos'
          }
        }
      };
    });
    final cloud = fakeApi((r) {
      expect(r.uri.host, 'api.cloudinary.com');
      expect(r.headers.containsKey('Authorization'), false);
      final form = r.data as FormData;
      expect(Map.fromEntries(form.fields), {
        'api_key': 'key',
        'signature': 'signed',
        'timestamp': '123',
        'folder': 'animals/photos'
      });
      expect(form.files.single.key, 'file');
      expect(form.files.single.value.filename, 'photo.jpg');
      return {'secure_url': 'https://res.cloudinary.com/demo/photo.jpg'};
    });
    expect(
        await StorageService(api: api, cloudinary: cloud).upload(
            XFile.fromData(Uint8List.fromList([1, 2, 3]),
                name: 'photo.jpg', path: 'photo.jpg'),
            folder: 'animals/photos'),
        'https://res.cloudinary.com/demo/photo.jpg');
  });
  test('Criação envia animalId numérico e tutorId', () async {
    final service = MonitoringService(
        api: fakeApi((r) {
          expect(r.path, '/monitoring');
          expect(r.data,
              {'animalId': 9, 'tutorId': 'tutor-id', 'notes': 'Acompanhar'});
          return {};
        }),
        storage: FakeStorage());
    await service.createMonitoring(
        animalId: 9, tutorId: 'tutor-id', notes: ' Acompanhar ');
  });
  for (final status in ['PENDING', 'REJECTED', 'APPROVED', 'IN_REVIEW']) {
    test('Envio no status $status', () async {
      final requests = <RequestOptions>[];
      final storage = FakeStorage();
      final service = MonitoringService(
          api: fakeApi((r) {
            requests.add(r);
            return {
              'data': {'id': 'm1', 'status': status}
            };
          }),
          storage: storage);
      final future = service.submitMonitoring(
          monitoringId: 'm1',
          video: fixture('video.mp4'),
          images: List.generate(5, (i) => fixture('$i.jpg')));
      if (status == 'PENDING' || status == 'REJECTED') {
        await future;
        expect(requests.last.path, '/monitoring/m1/submit');
        expect(requests.last.data['imageUrls'], hasLength(5));
        expect(requests.last.data['videoUrl'], contains('/video/'));
        expect(storage.calls, 6);
      } else {
        await expectLater(future, throwsStateError);
        expect(storage.calls, 0);
      }
    });
  }
  test('Falha no upload impede submit; fotos insuficientes são rejeitadas',
      () async {
    final service = MonitoringService(
        api: fakeApi((r) {
          expect(r.method, 'GET');
          return {
            'data': {'id': 'm1', 'status': 'PENDING'}
          };
        }),
        storage: FakeStorage(fail: true));
    await expectLater(
        service.submitMonitoring(
            monitoringId: 'm1',
            video: fixture('v'),
            images: List.generate(5, (i) => fixture('$i'))),
        throwsStateError);
    await expectLater(
        service.submitMonitoring(
            monitoringId: 'm1', video: fixture('v'), images: []),
        throwsArgumentError);
  });
  for (final approved in [true, false]) {
    test('Revisão envia approved=$approved', () async {
      final requests = <RequestOptions>[];
      final service = MonitoringService(
          api: fakeApi((r) {
            requests.add(r);
            return {
              'data': {'id': 'm1', 'status': 'IN_REVIEW'}
            };
          }),
          storage: FakeStorage());
      await service.reviewMonitoring(
          monitoringId: 'm1', approved: approved, notes: ' Revisado ');
      expect(requests.last.method, 'PATCH');
      expect(requests.last.data, {'approved': approved, 'notes': 'Revisado'});
    });
  }
  test('Revisão bloqueia monitoramento pendente', () async {
    final service = MonitoringService(
        api: fakeApi((r) {
          expect(r.method, 'GET');
          return {
            'data': {'status': 'PENDING'}
          };
        }),
        storage: FakeStorage());
    await expectLater(
        service.reviewMonitoring(monitoringId: 'm1', approved: true),
        throwsStateError);
  });
}
