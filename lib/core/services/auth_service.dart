import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/foundation.dart';
import '../api/api_client.dart';
import '../models/user_model.dart';

class AuthService {
  final _client = ApiClient();

  Future<UserModel> login(String email, String password) async {
    final response = await _client.dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    debugPrint('[AuthService] login response: ${response.data}');

    // A API retorna { success, data: { user, accessToken, refreshToken } }
    final body = response.data as Map<String, dynamic>;
    final data = (body['data'] ?? body) as Map<String, dynamic>;

    await _client.saveTokens(
      data['accessToken'] as String,
      data['refreshToken'] as String,
    );

    final userJson = (data['user'] as Map<String, dynamic>?) ?? data;
    return UserModel.fromJson(userJson);
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String phone,
    required String cpf,
    required String password,
    required String confirmPassword,
  }) async {
    final response = await _client.dio.post('/auth/register', data: {
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'cpf': cpf,
      'password': password,
      'confirmPassword': confirmPassword,
    });
    debugPrint('[AuthService] register response: ${response.data}');
  }

  Future<void> logout() async {
    final prefs = await SharedPreferences.getInstance();
    final refreshToken = prefs.getString(kRefreshTokenKey);
    if (refreshToken != null) {
      try {
        await _client.dio.post('/auth/logout', data: {'refreshToken': refreshToken});
      } catch (_) {}
    }
    await _client.clearTokens();
  }

  Future<void> forgotPassword(String email) async {
    final response = await _client.dio.post('/auth/forgot-password', data: {'email': email});
    debugPrint('[AuthService] forgotPassword response: ${response.data}');
  }

  Future<UserModel> getMe() async {
    final response = await _client.dio.get('/users/me');
    debugPrint('[AuthService] getMe response: ${response.data}');
    final body = response.data as Map<String, dynamic>;
    final userJson = (body['data'] ?? body) as Map<String, dynamic>;
    return UserModel.fromJson(userJson);
  }

  Future<bool> isLoggedIn() async {
    final token = await _client.getAccessToken();
    return token != null;
  }
}