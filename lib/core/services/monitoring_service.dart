import 'package:image_picker/image_picker.dart';
import 'storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/monitoring_model.dart';
import '../models/animal_model.dart';
import 'animal_service.dart';
import 'capture_attestation.dart';
import 'paged.dart';

class MonitoringService {
  final Dio api;
  final StorageService storage;
  final AnimalService animals;
  MonitoringService({Dio? api, StorageService? storage, AnimalService? animals})
      : api = api ?? ApiClient().dio,
        storage = storage ?? StorageService(),
        animals = animals ?? AnimalService(api: api);

  /// A API de monitoramento devolve o animal só com id, nome, espécie e raça
  /// (sem sexo, porte e fotos). Busca o cadastro completo de cada animal
  /// para que os cards mostrem os dados reais.
  Future<List<MonitoringModel>> _withAnimals(
    List<MonitoringModel> items, {
    bool bulk = false,
  }) async {
    final ids = items.map((m) => m.animalId).where((id) => id > 0).toSet();
    final found = <int, AnimalModel>{};
    // Equipe: uma única listagem completa evita uma requisição por animal.
    if (bulk && ids.length > 3) {
      try {
        for (final a in await animals.getAllAnimals()) {
          if (ids.contains(a.id)) found[a.id] = a;
        }
        return items.map((m) => m.withAnimal(found[m.animalId])).toList();
      } catch (e) {
        debugPrint('[MonitoringService] listagem de animais falhou: $e');
      }
    }
    await Future.wait(
      ids.map((id) async {
        try {
          found[id] = await animals.getAnimalById(id);
        } catch (e) {
          debugPrint('[MonitoringService] animal $id indisponível: $e');
        }
      }),
    );
    return items.map((m) => m.withAnimal(found[m.animalId])).toList();
  }

  /// TUTOR → todos os monitoramentos próprios (todas as páginas)
  Future<List<MonitoringModel>> getAllMyMonitorings() async {
    final items = await fetchAllPages((page, limit) async => _parseList(
        (await api.get('/monitoring/mine',
                queryParameters: {'page': page, 'limit': limit}))
            .data));
    return _withAnimals(items);
  }

  /// ADMIN/STAFF → todos os monitoramentos (todas as páginas)
  Future<List<MonitoringModel>> getEveryMonitoring() async {
    final items = await fetchAllPages((page, limit) async => _parseList(
        (await api.get('/monitoring',
                queryParameters: {'page': page, 'limit': limit}))
            .data));
    return _withAnimals(items, bulk: true);
  }

  /// TUTOR → GET /monitoring/mine
  Future<List<MonitoringModel>> getMyMonitorings({int page = 1}) async {
    debugPrint(
      '[MonitoringService] getMyMonitorings → GET /monitoring/mine?page=$page',
    );
    final response = await api.get(
      '/monitoring/mine',
      queryParameters: {'page': page},
    );
    return _withAnimals(_parseList(response.data));
  }

  /// ADMIN/STAFF → GET /monitoring
  Future<List<MonitoringModel>> getAllMonitorings({
    int page = 1,
    int limit = 20,
  }) async {
    debugPrint(
      '[MonitoringService] getAllMonitorings → GET /monitoring?page=$page',
    );
    final response = await api.get(
      '/monitoring',
      queryParameters: {'page': page, 'limit': limit},
    );
    return _withAnimals(_parseList(response.data));
  }

  /// TUTOR busca pelo /mine; ADMIN/STAFF busca direto por ID
  Future<MonitoringModel> getMonitoringById(
    String id, {
    bool isAdminOrStaff = false,
    bool withAnimal = true,
  }) async {
    final response = await api.get('/monitoring/$id');
    final m = MonitoringModel.fromJson(_unwrapSingle(response.data));
    if (!withAnimal) return m;
    return (await _withAnimals([m])).first;
  }

  Future<void> createMonitoring({
    required int animalId,
    required String tutorId,
    String? notes,
  }) async {
    if (animalId <= 0 || tutorId.trim().isEmpty) {
      throw ArgumentError('Selecione o animal e o tutor.');
    }
    await api.post(
      '/monitoring',
      data: {
        'animalId': animalId,
        'tutorId': tutorId,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
  }

  Future<void> submitMonitoring({
    required String monitoringId,
    required XFile video,
    required List<XFile> images,
    void Function(double)? onProgress,
  }) async {
    if (images.length != 5) throw ArgumentError('Adicione exatamente 5 fotos.');
    final current = await getMonitoringById(monitoringId, withAnimal: false);
    if (!current.canSubmit) {
      throw StateError('Este monitoramento não aceita envios.');
    }
    for (final file in [...images, video]) {
      if (await file.length() == 0) throw ArgumentError('Arquivo vazio.');
    }
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      urls.add(
        await storage.upload(
          images[i],
          folder: 'monitoring/images',
          onProgress: (sent, total) {
            if (total > 0) onProgress?.call((i + sent / total) / 6);
          },
        ),
      );
    }
    final videoUrl = await storage.upload(
      video,
      folder: 'monitoring/videos',
      resourceType: 'video',
      onProgress: (sent, total) {
        if (total > 0) onProgress?.call((5 + sent / total) / 6);
      },
    );
    await api.post(
      '/monitoring/$monitoringId/submit',
      data: {'videoUrl': videoUrl, 'imageUrls': urls},
    );
  }

  /// Sessão de captura: chave temporária para assinar cada foto/vídeo gravado.
  Future<CaptureSession> captureSession(String monitoringId) async {
    final response =
        await api.post('/monitoring/$monitoringId/capture-session');
    final body = response.data as Map;
    final data = Map<String, dynamic>.from((body['data'] ?? body) as Map);
    return CaptureSession.fromJson(monitoringId, data);
  }

  /// Última etapa do envio: registra na API as URLs já enviadas ao storage,
  /// com o atestado de captura de cada mídia.
  Future<void> finishSubmit({
    required String monitoringId,
    required String videoUrl,
    required List<String> imageUrls,
    required String captureToken,
    required List<Map<String, dynamic>> media,
  }) async {
    await api.post('/monitoring/$monitoringId/submit', data: {
      'videoUrl': videoUrl,
      'imageUrls': imageUrls,
      'captureToken': captureToken,
      'media': media,
    });
  }

  /// ADMIN → DELETE /monitoring/:id (apaga também as fotos e o vídeo).
  Future<void> deleteMonitoring(String monitoringId) async {
    await api.delete('/monitoring/$monitoringId');
  }

  Future<void> reviewMonitoring({
    required String monitoringId,
    required bool approved,
    String? notes,
  }) async {
    final current = await getMonitoringById(monitoringId, withAnimal: false);
    if (!current.isUnderReview) {
      throw StateError('Somente envios em análise podem ser revisados.');
    }
    debugPrint(
      '[MonitoringService] reviewMonitoring -> PATCH /monitoring/$monitoringId/review',
    );
    await api.patch(
      '/monitoring/$monitoringId/review',
      data: {
        'approved': approved,
        if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
      },
    );
  }

  // A API envelopa assim: { success, data: { data: [...], total, ... }, timestamp }
  // _parseList desembrulha os dois níveis até chegar na lista real.
  List<MonitoringModel> _parseList(dynamic body) {
    List<dynamic> items;

    if (body is List) {
      items = body;
    } else if (body is Map) {
      debugPrint('[MonitoringService] body keys: ${body.keys.toList()}');

      // 1º envelope: body['data'] pode ser { data: [...] } ou direto a lista
      final outer = body['data'] ?? body;

      if (outer is List) {
        items = outer;
      } else if (outer is Map) {
        debugPrint('[MonitoringService] outer keys: ${outer.keys.toList()}');
        // 2º envelope: outer['data'] é a lista real
        final inner =
            outer['data'] ?? outer['items'] ?? outer['monitorings'] ?? [];
        items = inner is List ? inner : [];
      } else {
        items = [];
      }
    } else {
      items = [];
    }

    debugPrint('[MonitoringService] items parsed: ${items.length}');
    return items
        .map((j) => MonitoringModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  // Desembrulha um objeto único: { success, data: {...} } → Map interno
  Map<String, dynamic> _unwrapSingle(dynamic body) {
    if (body is Map) {
      final outer = body['data'];
      if (outer is Map) return outer as Map<String, dynamic>;
      return body as Map<String, dynamic>;
    }
    return body as Map<String, dynamic>;
  }
}
