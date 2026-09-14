import 'package:image_picker/image_picker.dart';
import 'storage_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/monitoring_model.dart';

class MonitoringService {
  final Dio api;
  final StorageService storage;
  MonitoringService({Dio? api, StorageService? storage})
      : api = api ?? ApiClient().dio,
        storage = storage ?? StorageService();

  /// TUTOR → GET /monitoring/mine
  Future<List<MonitoringModel>> getMyMonitorings({int page = 1}) async {
    debugPrint(
        '[MonitoringService] getMyMonitorings → GET /monitoring/mine?page=$page');
    final response =
        await api.get('/monitoring/mine', queryParameters: {'page': page});
    return _parseList(response.data);
  }

  /// ADMIN/STAFF → GET /monitoring
  Future<List<MonitoringModel>> getAllMonitorings(
      {int page = 1, int limit = 20}) async {
    debugPrint(
        '[MonitoringService] getAllMonitorings → GET /monitoring?page=$page');
    final response = await api
        .get('/monitoring', queryParameters: {'page': page, 'limit': limit});
    return _parseList(response.data);
  }

  /// TUTOR busca pelo /mine; ADMIN/STAFF busca direto por ID
  Future<MonitoringModel> getMonitoringById(String id,
      {bool isAdminOrStaff = false}) async {
    final response = await api.get('/monitoring/$id');
    return MonitoringModel.fromJson(_unwrapSingle(response.data));
  }

  Future<void> createMonitoring(
      {required int animalId, required String tutorId, String? notes}) async {
    if (animalId <= 0 || tutorId.trim().isEmpty) {
      throw ArgumentError('Selecione o animal e o tutor.');
    }
    await api.post('/monitoring', data: {
      'animalId': animalId,
      'tutorId': tutorId,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
  }

  Future<void> submitMonitoring({
    required String monitoringId,
    required XFile video,
    required List<XFile> images,
    void Function(double)? onProgress,
  }) async {
    if (images.length != 5) throw ArgumentError('Adicione exatamente 5 fotos.');
    final current = await getMonitoringById(monitoringId);
    if (!current.canSubmit) {
      throw StateError('Este monitoramento não aceita envios.');
    }
    for (final file in [...images, video]) {
      if (await file.length() == 0) throw ArgumentError('Arquivo vazio.');
    }
    final urls = <String>[];
    for (var i = 0; i < images.length; i++) {
      urls.add(await storage.upload(images[i], folder: 'monitoring/images',
          onProgress: (sent, total) {
        if (total > 0) onProgress?.call((i + sent / total) / 6);
      }));
    }
    final videoUrl = await storage.upload(video,
        folder: 'monitoring/videos',
        resourceType: 'video', onProgress: (sent, total) {
      if (total > 0) onProgress?.call((5 + sent / total) / 6);
    });
    await api.post('/monitoring/$monitoringId/submit', data: {
      'videoUrl': videoUrl,
      'imageUrls': urls,
    });
  }

  Future<void> reviewMonitoring({
    required String monitoringId,
    required bool approved,
    String? notes,
  }) async {
    final current = await getMonitoringById(monitoringId);
    if (!current.isUnderReview) {
      throw StateError('Somente envios em análise podem ser revisados.');
    }
    debugPrint(
        '[MonitoringService] reviewMonitoring -> PATCH /monitoring/$monitoringId/review');
    await api.patch('/monitoring/$monitoringId/review', data: {
      'approved': approved,
      if (notes != null && notes.trim().isNotEmpty) 'notes': notes.trim(),
    });
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
