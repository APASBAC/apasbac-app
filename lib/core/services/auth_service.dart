import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../api/api_client.dart';
import '../models/user_model.dart';

const String kLastEmailKey = 'last_login_email';

class AuthService {
  final ApiClient _client;
  AuthService({ApiClient? client}) : _client = client ?? ApiClient();

  /// Avisa quando a sessão expirou de vez (refresh recusado pela API).
  ApiClient get client => _client;

  Map<String, dynamic> _data(dynamic body) {
    final map = body as Map<String, dynamic>;
    final data = map['data'];
    return data is Map<String, dynamic> ? data : map;
  }

  Future<UserModel> _startSession(
      Map<String, dynamic> data, bool remember, String email) async {
    final access = data['accessToken'] as String?;
    final refresh = data['refreshToken'] as String?;
    if (access == null || refresh == null) {
      throw StateError('A API não retornou a sessão.');
    }
    await _client.saveTokens(access, refresh, remember: remember);
    final userJson = (data['user'] as Map<String, dynamic>?) ?? data;
    await _client.cacheUser(userJson);
    final prefs = await SharedPreferences.getInstance();
    if (remember) {
      await prefs.setString(kLastEmailKey, email.trim());
    } else {
      await prefs.remove(kLastEmailKey);
    }
    return UserModel.fromJson(userJson);
  }

  Future<UserModel> login(String email, String password,
      {bool remember = true}) async {
    final response = await _client.dio.post('/auth/login', data: {
      'email': email.trim(),
      'password': password,
    });
    return _startSession(_data(response.data), remember, email);
  }

  /// O cadastro já devolve a sessão: não é preciso um segundo login.
  Future<UserModel> register({
    required String fullName,
    required String email,
    required String phone,
    required String cpf,
    required String password,
    required String confirmPassword,
    bool remember = true,
  }) async {
    final response = await _client.dio.post('/auth/register', data: {
      'fullName': fullName,
      'email': email,
      'phone': phone,
      'cpf': cpf,
      'password': password,
      'confirmPassword': confirmPassword,
    });
    final data = _data(response.data);
    if (data['accessToken'] == null) {
      return login(email, password, remember: remember);
    }
    return _startSession(data, remember, email);
  }

  /// Encerra a sessão na API (invalida o refresh token) e no aparelho.
  Future<void> logout() async {
    final refreshToken = await _client.getRefreshToken();
    if (refreshToken != null) {
      try {
        await _client.dio.post('/auth/logout', data: {
          'refreshToken': refreshToken
        }).timeout(const Duration(seconds: 8));
      } catch (_) {}
    }
    await _client.clearTokens();
  }

  Future<void> forgotPassword(String email) async {
    await _client.dio.post('/auth/forgot-password', data: {'email': email});
  }

  Future<UserModel> getMe() async {
    final response = await _client.dio.get('/users/me');
    final json = _data(response.data);
    await _client.cacheUser(json);
    return UserModel.fromJson(json);
  }

  Future<bool> isLoggedIn() => _client.hasSession();

  /// Abre o app com a sessão guardada. Sem internet, usa o último usuário
  /// salvo; com a sessão recusada pela API, volta ao login.
  Future<UserModel?> restoreSession() async {
    if (!await _client.hasSession()) return null;
    try {
      return await getMe();
    } on DioException catch (e) {
      if (!await _client.hasSession()) return null;
      final status = e.response?.statusCode;
      if (status == 401 || status == 403) {
        await _client.clearTokens();
        return null;
      }
      final cached = await _client.cachedUser();
      return cached == null ? null : UserModel.fromJson(cached);
    }
  }

  Future<String?> lastEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kLastEmailKey);
  }

  Future<bool> rememberMe() => _client.rememberMe();
}
