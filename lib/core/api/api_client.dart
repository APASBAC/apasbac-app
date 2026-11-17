import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../update/update_interceptor.dart';

const String kBaseUrl = 'https://apasbac-api.vercel.app/api/v1';
const String kAccessTokenKey = 'access_token';
const String kRefreshTokenKey = 'refresh_token';
const String kRememberMeKey = 'remember_me';
const String kCachedUserKey = 'cached_user';

/// Onde a sessão é guardada. Em produção, o armazenamento seguro do Android
/// (Keystore); nos testes, memória.
abstract class SessionStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class SecureSessionStorage implements SessionStorage {
  const SecureSessionStorage();
  static const _storage = FlutterSecureStorage();
  @override
  Future<String?> read(String key) async {
    try {
      return await _storage.read(key: key);
    } catch (_) {
      return null; // armazenamento corrompido nunca derruba o app
    }
  }

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);
  @override
  Future<void> delete(String key) async {
    try {
      await _storage.delete(key: key);
    } catch (_) {}
  }
}

class MemorySessionStorage implements SessionStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async => values[key] = value;
  @override
  Future<void> delete(String key) async => values.remove(key);
}

/// Cliente HTTP da API com sessão JWT.
///
/// - Access token curto (15 min) e refresh token (7 dias) com **rotação**:
///   cada renovação devolve um par novo e o antigo deixa de valer. Reusar um
///   refresh token já trocado encerra a sessão na API, por isso só existe
///   uma renovação por vez (as requisições simultâneas esperam a mesma).
/// - O access token é renovado um pouco antes de expirar; se mesmo assim vier
///   401, renova e repete a requisição uma vez.
/// - "Lembrar de mim": com a opção marcada a sessão fica no armazenamento
///   seguro e sobrevive ao fechar o app; desmarcada, fica só na memória.
/// - Se a API recusar o refresh (expirado/revogado), a sessão é apagada e
///   [sessionExpired] avisa o app para voltar ao login.
class ApiClient {
  static final ApiClient _instance = ApiClient.custom();
  factory ApiClient() => _instance;

  late final Dio dio;
  late final Dio _refreshDio;
  final SessionStorage _storage;

  String? _access, _refresh;
  bool _remember = true;
  Future<void>? _loading;
  Future<bool>? _refreshing;

  /// Incrementa quando a sessão expira de vez (refresh recusado pela API).
  final sessionExpired = ValueNotifier<int>(0);

  static const _publicAuthPaths = {
    '/auth/login',
    '/auth/register',
    '/auth/refresh',
    '/auth/forgot-password',
    '/auth/reset-password',
  };

  ApiClient.custom({
    SessionStorage storage = const SecureSessionStorage(),
    HttpClientAdapter? adapter,
    String baseUrl = kBaseUrl,
  }) : _storage = storage {
    dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 30),
      headers: {'Content-Type': 'application/json'},
    ));
    _refreshDio = Dio(BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 30)));
    if (adapter != null) {
      dio.httpClientAdapter = adapter;
      _refreshDio.httpClientAdapter = adapter;
    }
    dio.interceptors.add(AppVersionInterceptor());
    _refreshDio.interceptors.add(AppVersionInterceptor());
    dio.interceptors.add(InterceptorsWrapper(
      onRequest: _onRequest,
      onError: _onError,
    ));
  }

  // ── Sessão ────────────────────────────────────────────────

  Future<void> _ensureLoaded() => _loading ??= _load();

  Future<void> _load() async {
    _remember = await _storage.read(kRememberMeKey) != 'false';
    if (_remember) {
      _access = await _storage.read(kAccessTokenKey);
      _refresh = await _storage.read(kRefreshTokenKey);
    } else {
      // Sem "lembrar de mim": a sessão anterior terminou quando o app fechou.
      await _deleteStored();
    }
  }

  Future<void> _deleteStored() async {
    await _storage.delete(kAccessTokenKey);
    await _storage.delete(kRefreshTokenKey);
    await _storage.delete(kCachedUserKey);
  }

  /// Há sessão (o access token pode estar vencido; o refresh resolve).
  Future<bool> hasSession() async {
    await _ensureLoaded();
    return _refresh != null || _access != null;
  }

  Future<bool> rememberMe() async {
    await _ensureLoaded();
    return _remember;
  }

  Future<void> saveTokens(String access, String refresh,
      {bool? remember}) async {
    await _ensureLoaded();
    if (remember != null) {
      _remember = remember;
      await _storage.write(kRememberMeKey, remember.toString());
    }
    _access = access;
    _refresh = refresh;
    if (_remember) {
      await _storage.write(kAccessTokenKey, access);
      await _storage.write(kRefreshTokenKey, refresh);
    } else {
      await _deleteStored();
    }
  }

  Future<void> clearTokens() async {
    await _ensureLoaded();
    _access = null;
    _refresh = null;
    await _deleteStored();
  }

  Future<String?> getAccessToken() async {
    await _ensureLoaded();
    return _access;
  }

  Future<String?> getRefreshToken() async {
    await _ensureLoaded();
    return _refresh;
  }

  /// Guarda o usuário para abrir o app sem internet (só com "lembrar de mim").
  Future<void> cacheUser(Map<String, dynamic> json) async {
    await _ensureLoaded();
    if (_remember) await _storage.write(kCachedUserKey, jsonEncode(json));
  }

  Future<Map<String, dynamic>?> cachedUser() async {
    await _ensureLoaded();
    try {
      final raw = await _storage.read(kCachedUserKey);
      return raw == null ? null : jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return null;
    }
  }

  // ── Renovação ─────────────────────────────────────────────

  /// Segundos até o JWT expirar (null se não der para ler).
  @visibleForTesting
  static int? secondsLeft(String jwt, {DateTime? now}) {
    try {
      final parts = jwt.split('.');
      if (parts.length != 3) return null;
      final payload = jsonDecode(
              utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))))
          as Map<String, dynamic>;
      final exp = payload['exp'];
      if (exp is! num) return null;
      final nowS = (now ?? DateTime.now()).millisecondsSinceEpoch ~/ 1000;
      return exp.toInt() - nowS;
    } catch (_) {
      return null;
    }
  }

  /// Renova a sessão. Chamadas simultâneas compartilham a mesma renovação.
  Future<bool> refreshSession() {
    final running = _refreshing;
    if (running != null) return running;
    final future = _doRefresh();
    _refreshing = future;
    future.whenComplete(() {
      if (identical(_refreshing, future)) _refreshing = null;
    });
    return future;
  }

  Future<bool> _doRefresh() async {
    await _ensureLoaded();
    final used = _refresh;
    if (used == null) return false;
    try {
      final response =
          await _refreshDio.post('/auth/refresh', data: {'refreshToken': used});
      final body = response.data as Map;
      final data = (body['data'] ?? body) as Map;
      final access = data['accessToken'] as String?;
      if (access == null) return false;
      await saveTokens(access, (data['refreshToken'] as String?) ?? used);
      return true;
    } on DioException catch (e) {
      final status = e.response?.statusCode;
      // Só a API dizendo "inválido" encerra a sessão. Sem internet, versão
      // obrigatória (426) ou erro do servidor mantêm o login.
      if ((status == 401 || status == 403) && _refresh == used) {
        await clearTokens();
        sessionExpired.value++;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static bool _isPublicAuth(String path) =>
      _publicAuthPaths.any((p) => path == p || path.endsWith(p));

  Future<void> _onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    if (kDebugMode) {
      debugPrint('[ApiClient] → ${options.method} ${options.path}');
    }
    if (_isPublicAuth(options.path)) return handler.next(options);
    try {
      await _ensureLoaded();
      if (_refresh != null) {
        final left = _access == null ? null : secondsLeft(_access!);
        // Sem access token ou vencendo em menos de 1 minuto: renova antes.
        if (_access == null || (left != null && left < 60)) {
          await refreshSession();
        }
      }
      if (_access != null) {
        options.headers['Authorization'] = 'Bearer $_access';
      }
    } catch (_) {}
    handler.next(options);
  }

  Future<void> _onError(
      DioException error, ErrorInterceptorHandler handler) async {
    if (kDebugMode) {
      debugPrint('[ApiClient] erro ${error.response?.statusCode} '
          '${error.requestOptions.path}');
    }
    final opts = error.requestOptions;
    if (error.response?.statusCode != 401 ||
        opts.extra['retried'] == true ||
        _isPublicAuth(opts.path) ||
        _refresh == null) {
      return handler.next(error);
    }
    // Outra requisição pode já ter renovado enquanto esta estava no ar.
    final sent = opts.headers['Authorization'];
    final renewed = (_access != null && sent != 'Bearer $_access')
        ? true
        : await refreshSession();
    if (!renewed || _access == null) return handler.next(error);
    opts.extra['retried'] = true;
    opts.headers['Authorization'] = 'Bearer $_access';
    try {
      return handler.resolve(await dio.fetch(opts));
    } on DioException catch (e) {
      return handler.next(e);
    } catch (_) {
      return handler.next(error);
    }
  }
}
