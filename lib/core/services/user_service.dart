import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/user_model.dart';

class UserService {
  final _client = ApiClient();

  Future<List<UserModel>> getUsers({int page = 1, int limit = 100}) async {
    debugPrint('[UserService] getUsers -> GET /users?page=$page');
    final response = await _client.dio.get('/users', queryParameters: {
      'page': page,
      'limit': limit,
    });
    return _parseList(response.data);
  }

  Future<void> updateRole(String userId, String role) async {
    debugPrint('[UserService] updateRole -> PATCH /users/$userId/role');
    await _client.dio.patch('/users/$userId/role', data: {'role': role});
  }

  List<UserModel> _parseList(dynamic body) {
    List<dynamic> items;

    if (body is List) {
      items = body;
    } else if (body is Map) {
      final outer = body['data'] ?? body;
      if (outer is List) {
        items = outer;
      } else if (outer is Map) {
        final inner = outer['data'] ?? outer['items'] ?? outer['users'] ?? [];
        items = inner is List ? inner : [];
      } else {
        items = [];
      }
    } else {
      items = [];
    }

    return items
        .map((j) => UserModel.fromJson(j as Map<String, dynamic>))
        .toList();
  }
}
