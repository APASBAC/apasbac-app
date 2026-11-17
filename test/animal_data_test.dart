import 'package:apasbac_app/core/models/animal_model.dart';
import 'package:apasbac_app/core/models/monitoring_model.dart';
import 'package:apasbac_app/core/services/animal_service.dart';
import 'package:apasbac_app/core/services/monitoring_service.dart';
import 'package:apasbac_app/core/utils/image_url.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

Dio _fake(Map<String, dynamic> Function(String path) answer) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(
      onRequest: (o, h) => h.resolve(
          Response(requestOptions: o, statusCode: 200, data: answer(o.path)))));
  return dio;
}

void main() {
  test('URLs do Cloudinary viram JPG redimensionado em HTTPS', () {
    expect(
        normalizeImageUrl(
            ' http://res.cloudinary.com/demo/image/upload/v1/animals/photos/a.heic '),
        'https://res.cloudinary.com/demo/image/upload/f_jpg,q_auto,c_limit,w_1080/v1/animals/photos/a.heic');
    expect(normalizeImageUrl('https://drive.google.com/file/d/abc/view'),
        'https://drive.google.com/uc?export=view&id=abc');
    expect(normalizeImageUrl(null), '');
  });

  test('Sexo desconhecido não vira Fêmea; macho é reconhecido', () {
    expect(AnimalModel.fromJson({'name': 'Rex'}).sexLabel, '');
    expect(AnimalModel.fromJson({'sex': 'MALE'}).sexLabel, 'Macho');
    expect(AnimalModel.fromJson({'sex': 'FEMALE'}).sexLabel, 'Fêmea');
    expect(AnimalModel.fromJson({'breed': 'SRD', 'sex': 'MALE'}).summary,
        'SRD · Macho');
  });

  test('Monitoramento usa os dados completos do animal', () async {
    final dio = _fake((path) => switch (path) {
          '/monitoring/mine' => {
              'success': true,
              'data': [
                {
                  'id': 'm1',
                  'animalId': 7,
                  'status': 'PENDING',
                  'animal': {
                    'id': 7,
                    'name': 'Rex',
                    'species': 'Cão',
                    'breed': 'SRD'
                  }
                }
              ]
            },
          '/animals/public/7' => {
              'success': true,
              'data': {
                'name': 'Rex',
                'breed': 'Vira-lata',
                'sex': 'MALE',
                'size': 'MEDIUM',
                'photos': [
                  'https://res.cloudinary.com/demo/image/upload/v1/r.jpg'
                ]
              }
            },
          _ => {},
        });
    final svc = MonitoringService(api: dio, animals: AnimalService(api: dio));
    final List<MonitoringModel> list = await svc.getMyMonitorings();
    final animal = list.single.animal!;
    expect(animal.id, 7);
    expect(animal.sexLabel, 'Macho');
    expect(animal.breed, 'Vira-lata');
    expect(animal.primaryPhoto!.url, contains('/image/upload/f_jpg'));
  });
}
