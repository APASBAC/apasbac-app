import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../update/update_interceptor.dart';

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

    _refreshDio = Dio(BaseOptions(
        baseUrl: kBaseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30)));
    dio.interceptors.add(AppVersionInterceptor());
    _refreshDio.interceptors.add(AppVersionInterceptor());

    dio.interceptors.add(InterceptorsWrapper(
      onRequest: (options, handler) async {
        if (kDebugMode) {
          debugPrint('[ApiClient] → ${options.method} ${options.path}');
        }

        final token = await _storage.read(key: kAccessTokenKey);
        if (token != null) {
          options.headers['Authorization'] = 'Bearer $token';
        }

        return handler.next(options);
      },
      onResponse: (response, handler) {
        if (kDebugMode) {
          debugPrint(
              '[ApiClient] ← ${response.statusCode} ${response.requestOptions.path}');
        }
        return handler.next(response);
      },
      onError: (error, handler) async {
        if (kDebugMode) {
          debugPrint(
              '[ApiClient] erro ${error.response?.statusCode} ${error.type}');
        }

        if (error.response?.statusCode == 401 &&
            error.requestOptions.extra['retried'] != true) {
          final refreshed = await _tryRefresh();
          if (refreshed) {
            final token = await _storage.read(key: kAccessTokenKey);
            final opts = error.requestOptions;
            opts.extra['retried'] = true;
            opts.headers['Authorization'] = 'Bearer $token';
            try {
              final response = await dio.fetch(opts);
              return handler.resolve(response);
            } catch (_) {
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
    if (refreshToken == null) return false;
    try {
      final response = await _refreshDio.post('/auth/refresh', data: {
        'refreshToken': refreshToken,
      });
      final body = response.data as Map<String, dynamic>;
      final data = (body['data'] ?? body) as Map<String, dynamic>;
      await _storage.write(key: kAccessTokenKey, value: data['accessToken']);
      if (data['refreshToken'] != null) {
        await _storage.write(
            key: kRefreshTokenKey, value: data['refreshToken']);
      }
      return true;
    } on DioException catch (e) {
      // A required update or temporary outage must never erase the user's login.
      if (e.response?.statusCode != 401 && e.response?.statusCode != 403) {
        return false;
      }
      await _storage.deleteAll();
      return false;
    } catch (_) {
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
