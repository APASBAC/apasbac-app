import 'dart:convert';
import 'dart:typed_data';

import 'package:apasbac_app/core/api/api_client.dart';
import 'package:apasbac_app/core/services/auth_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

String jwt(int secondsFromNow, [String tag = '']) {
  String b64(Object o) =>
      base64Url.encode(utf8.encode(jsonEncode(o))).replaceAll('=', '');
  final exp = DateTime.now().millisecondsSinceEpoch ~/ 1000 + secondsFromNow;
  return '${b64({'alg': 'HS256'})}.${b64({'exp': exp, 't': tag})}.sig';
}

/// API falsa: valida o access token e aplica rotação no refresh.
class FakeApi implements HttpClientAdapter {
  String validAccess = '';
  String validRefresh = '';
  int refreshCalls = 0, logoutCalls = 0;
  bool refreshRejects = false, offline = false;
  final requests = <String>[];

  ResponseBody json(Object body, int status) =>
      ResponseBody.fromString(jsonEncode(body), status, headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType]
      });

  @override
  Future<ResponseBody> fetch(
      RequestOptions o, Stream<Uint8List>? body, Future<void>? cancel) async {
    requests.add('${o.method} ${o.path}');
    if (offline) {
      throw DioException.connectionError(requestOptions: o, reason: 'offline');
    }
    await Future<void>.delayed(const Duration(milliseconds: 5));
    switch (o.path) {
      case '/auth/login':
        final ok = (o.data as Map)['password'] == 'certa';
        if (!ok) return json({'message': 'Credenciais inválidas'}, 401);
        validAccess = jwt(900, 'a0');
        validRefresh = 'r0';
        return json({
          'success': true,
          'data': {
            'user': {'id': 'u1', 'fullName': 'Ana', 'role': 'TUTOR'},
            'accessToken': validAccess,
            'refreshToken': validRefresh,
          }
        }, 200);
      case '/auth/refresh':
        refreshCalls++;
        final sent = (o.data as Map)['refreshToken'];
        if (refreshRejects || sent != validRefresh) {
          return json({'message': 'Refresh token inválido'}, 401);
        }
        validAccess = jwt(900, 'a$refreshCalls');
        validRefresh = 'r$refreshCalls'; // rotação: o anterior deixa de valer
        return json({
          'success': true,
          'data': {'accessToken': validAccess, 'refreshToken': validRefresh}
        }, 200);
      case '/auth/logout':
        logoutCalls++;
        return json({'success': true}, 200);
      default:
        if (o.headers['Authorization'] != 'Bearer $validAccess') {
          return json({'message': 'Unauthorized'}, 401);
        }
        return json({
          'success': true,
          'data': {'id': 'u1', 'fullName': 'Ana', 'role': 'TUTOR'}
        }, 200);
    }
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('lê a validade do JWT', () {
    expect(ApiClient.secondsLeft(jwt(120))! > 100, isTrue);
    expect(ApiClient.secondsLeft('lixo'), isNull);
  });

  test('401 renova uma única vez para várias requisições simultâneas',
      () async {
    final api = FakeApi();
    final client = ApiClient.custom(
        storage: MemorySessionStorage(), adapter: api, baseUrl: 'https://t');
    await AuthService(client: client).login('a@x', 'certa');
    api.validAccess = 'outro'; // simula access token recusado pela API
    final results =
        await Future.wait(List.generate(5, (_) => client.dio.get('/users/me')));
    expect(results.every((r) => r.statusCode == 200), isTrue);
    expect(api.refreshCalls, 1, reason: 'rotação exige um refresh por vez');
    expect(await client.getRefreshToken(), 'r1');
  });

  test('access token perto de vencer é renovado antes da requisição', () async {
    final api = FakeApi();
    final storage = MemorySessionStorage();
    final client =
        ApiClient.custom(storage: storage, adapter: api, baseUrl: 'https://t');
    api.validRefresh = 'r0';
    await client.saveTokens(jwt(30), 'r0', remember: true);
    final r = await client.dio.get('/users/me');
    expect(r.statusCode, 200);
    expect(api.refreshCalls, 1);
    expect(api.requests.where((x) => x == 'GET /users/me').length, 1,
        reason: 'renovou antes, sem tomar 401');
  });

  test('refresh recusado encerra a sessão e avisa o app', () async {
    final api = FakeApi();
    final client = ApiClient.custom(
        storage: MemorySessionStorage(), adapter: api, baseUrl: 'https://t');
    await AuthService(client: client).login('a@x', 'certa');
    var expired = 0;
    client.sessionExpired.addListener(() => expired++);
    api
      ..validAccess = 'outro'
      ..refreshRejects = true;
    await expectLater(
        client.dio.get('/users/me'), throwsA(isA<DioException>()));
    expect(expired, 1);
    expect(await client.hasSession(), isFalse);
  });

  test('sem internet a sessão é mantida', () async {
    final api = FakeApi();
    final client = ApiClient.custom(
        storage: MemorySessionStorage(), adapter: api, baseUrl: 'https://t');
    await AuthService(client: client).login('a@x', 'certa');
    api.offline = true;
    await client.saveTokens(jwt(10), 'r0');
    await expectLater(
        client.dio.get('/users/me'), throwsA(isA<DioException>()));
    expect(await client.hasSession(), isTrue);
  });

  test('senha errada não tenta refresh', () async {
    final api = FakeApi();
    final client = ApiClient.custom(
        storage: MemorySessionStorage(), adapter: api, baseUrl: 'https://t');
    await expectLater(AuthService(client: client).login('a@x', 'errada'),
        throwsA(isA<DioException>()));
    expect(api.refreshCalls, 0);
  });

  test('Lembrar de mim guarda a sessão e o e-mail para a próxima abertura',
      () async {
    final storage = MemorySessionStorage();
    final api = FakeApi();
    final auth = AuthService(
        client: ApiClient.custom(
            storage: storage, adapter: api, baseUrl: 'https://t'));
    await auth.login(' ana@x ', 'certa', remember: true);
    // "Reabre" o app com o mesmo armazenamento.
    final reopened = AuthService(
        client: ApiClient.custom(
            storage: storage, adapter: api, baseUrl: 'https://t'));
    expect((await reopened.restoreSession())?.fullName, 'Ana');
    expect(await reopened.lastEmail(), 'ana@x');
    expect(await reopened.rememberMe(), isTrue);
  });

  test('Sem lembrar de mim a sessão acaba ao fechar o app', () async {
    final storage = MemorySessionStorage();
    final api = FakeApi();
    final auth = AuthService(
        client: ApiClient.custom(
            storage: storage, adapter: api, baseUrl: 'https://t'));
    await auth.login('ana@x', 'certa', remember: false);
    expect(storage.values.containsKey(kRefreshTokenKey), isFalse);
    expect((await auth.getMe()).fullName, 'Ana', reason: 'vale nesta abertura');
    final reopened = AuthService(
        client: ApiClient.custom(
            storage: storage, adapter: api, baseUrl: 'https://t'));
    expect(await reopened.restoreSession(), isNull);
    expect(await reopened.lastEmail(), isNull);
    expect(await reopened.rememberMe(), isFalse);
  });

  test('sem internet ao abrir usa o último usuário salvo', () async {
    final storage = MemorySessionStorage();
    final api = FakeApi();
    await AuthService(
            client: ApiClient.custom(
                storage: storage, adapter: api, baseUrl: 'https://t'))
        .login('ana@x', 'certa');
    api.offline = true;
    final reopened = AuthService(
        client: ApiClient.custom(
            storage: storage, adapter: api, baseUrl: 'https://t'));
    expect((await reopened.restoreSession())?.fullName, 'Ana');
  });

  test('sair encerra a sessão na API e no aparelho', () async {
    final storage = MemorySessionStorage();
    final api = FakeApi();
    final auth = AuthService(
        client: ApiClient.custom(
            storage: storage, adapter: api, baseUrl: 'https://t'));
    await auth.login('ana@x', 'certa');
    await auth.logout();
    expect(api.logoutCalls, 1);
    expect(await auth.isLoggedIn(), isFalse);
    expect(storage.values.containsKey(kAccessTokenKey), isFalse);
  });
}
