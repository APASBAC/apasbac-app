import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

const String kBaseUrl = 'https://apasbac-api.vercel.app/api/v1';
const String kAccessTokenKey = 'access_token';
const String kRefreshTokenKey = 'refresh_token';

class ApiClient {
  static final ApiClient _instance = ApiClient._internal();
  factory ApiClient() => _instance;

  late final Dio dio;
  late final Dio _refreshDio;
  final _storage = const FlutterSecureStorage();

  ApiClient._internal() {
    dio = Dio(BaseOptions(
      baseUrl: kBaseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));

    _refreshDio = Dio(BaseOptions(baseUrl: kBaseUrl));

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        debugPrint('[ApiClient] → ${options.method} ${options.baseUrl}${options.path}');
        debugPrint('[ApiClient]   queryParams: ${options.queryParameters}');

        final token = await _storage.read(key: kAccessTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        } else {
          debugPrint('[ApiClient]   ⚠️ NENHUM TOKEN encontrado no storage!');
        }

        return handler.next(options);
      },
      onResponse: (response, handler) {
        debugPrint('[ApiClient] ← ${response.statusCode} ${response.requestOptions.path}');
        return handler.next(response);
      },
      onError: (error, handler) async {
        debugPrint('[ApiClient] ✗ ERRO ${error.response?.statusCode} ${error.requestOptions.path}');
        debugPrint('[ApiClient]   tipo: ${error.type}');
        debugPrint('[ApiClient]   mensagem: ${error.message}');
        debugPrint('[ApiClient]   response.data: ${error.response?.data}');

        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['retried'] != true) {
          debugPrint('[ApiClient]   401 → tentando refresh token...');
          final refreshed = await _tryRefresh();
          debugPrint('[ApiClient]   refresh resultado: $refreshed');
          if (refreshed) {
            final token = await _storage.read(key: kAccessTokenKey);
            final opts = error.requestOptions;
            opts.extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              debugPrint('[ApiClient]   retry após refresh...');
              final response = await dio.fetch(opts);
              return handler.resolve(response);
            } catch (e) {
              debugPrint('[ApiClient]   retry falhou: $e');
              return handler.next(error);
            }
          }
        }

        return handler.next(error);
      },
    ));
  }

  Future<bool> _tryRefresh() async {
    final refreshToken = await _storage.read(key: kRefreshTokenKey);
    debugPrint('[ApiClient] _tryRefresh → refreshToken presente: ${refreshToken != null}');
    if (refreshToken == null) return false;
    try {
      final response = await _refreshDio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });
      final data = response.data;
      debugPrint('[ApiClient] _tryRefresh → sucesso, novos tokens recebidos');
      await _storage.write(key: kAccessTokenKey, value: data['accessToken']);
      if (data['refreshToken'] != null) {
        await _storage.write(key: kRefreshTokenKey, value: data['refreshToken']);
      }
      return true;
    } catch (e) {
      debugPrint('[ApiClient] _tryRefresh → falhou: $e');
      await _storage.deleteAll();
      return false;
    }
  }

  Future<void> saveTokens(String access, String refresh) async {
    await _storage.write(key: kAccessTokenKey, value: access);
    await _storage.write(key: kRefreshTokenKey, value: refresh);
  }

  Future<void> clearTokens() async {
    await _storage.deleteAll();
  }

  Future<String?> getAccessToken() => _storage.read(key: kAccessTokenKey);
}
