import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import '../models/create_animal.dart';
import '../api/api_client.dart';
import '../models/animal_model.dart';

class AnimalService {
  final Dio api;
  AnimalService({Dio? api}) : api = api ?? ApiClient().dio;

  Future<void> createAnimal(CreateAnimal animal) async {
    await api.post('/animals', data: animal.toJson());
  }

  Future<List<AnimalModel>> getAnimals({
    bool? isAdopted,
    int page = 1,
    int limit = 100,
  }) async {
    debugPrint('[AnimalService] getAnimals -> GET /animals');
    final response = await api.get('/animals', queryParameters: {
      if (isAdopted != null) 'isAdopted': isAdopted,
      'limit': limit,
      'page': page,
    });
    return _parseList(response.data);
  }

  Future<List<AnimalModel>> getMyAnimals(String userId) async {
    debugPrint('[AnimalService] getMyAnimals → GET /animals?isAdopted=true');
    final response = await api.get('/animals', queryParameters: {
      'isAdopted': true,
      'limit': 100,
      'page': 1,
    });

    final items = _parseList(response.data);

    debugPrint('[AnimalService] animais recebidos: ${items.length}');
    return items.where((a) => a.adoptedById == userId).toList();
  }

  // Rota pública — qualquer usuário autenticado ou não pode acessar
  Future<AnimalModel> getAnimalById(int id) async {
    debugPrint('[AnimalService] getAnimalById($id) → GET /animals/public/$id');
    final response = await api.get('/animals/public/$id');
    final body = response.data;
    // Desembrulha envelope { success, data: {...} }
    final json = (body is Map && body['data'] != null && body['data'] is Map)
        ? body['data'] as Map<String, dynamic>
        : body as Map<String, dynamic>;
    return AnimalModel.fromJson(json);
  }

  // Admin/Staff: busca completo com dados sensíveis
  Future<AnimalModel> getAnimalAdmin(int id) async {
    debugPrint('[AnimalService] getAnimalAdmin($id) → GET /animals/$id');
    final response = await api.get('/animals/$id');
    final body = response.data;
    final json = (body is Map && body['data'] != null && body['data'] is Map)
        ? body['data'] as Map<String, dynamic>
        : body as Map<String, dynamic>;
    return AnimalModel.fromJson(json);
  }

  Future<AnimalModel> getAnimalByUuid(String uuid) async {
    debugPrint(
        '[AnimalService] getAnimalByUuid($uuid) → GET /animals/public/uuid/$uuid');
    final response = await api.get('/animals/public/uuid/$uuid');
    final body = response.data;
    final json = (body is Map && body['data'] != null && body['data'] is Map)
        ? body['data'] as Map<String, dynamic>
        : body as Map<String, dynamic>;
    return AnimalModel.fromJson(json);
  }

  Future<void> linkAdopter({
    required int animalId,
    required String userId,
  }) async {
    debugPrint(
        '[AnimalService] linkAdopter($animalId) -> POST /animals/$animalId/adopter');
    await api.post('/animals/$animalId/adopter', data: {
      'userId': userId,
    });
  }

  List<AnimalModel> _parseList(dynamic body) {
    List<dynamic> items;

    if (body is List) {
      items = body;
    } else if (body is Map) {
      final outer = body['data'] ?? body;
      if (outer is List) {
        items = outer;
      } else if (outer is Map) {
        final inner = outer['data'] ?? outer['items'] ?? outer['animals'] ?? [];
        items = inner is List ? inner : [];
      } else {
        items = [];
      }
    } else {
      items = [];
    }

    return items
        .map((j) => AnimalModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
