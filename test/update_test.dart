import 'dart:async';
import 'dart:convert';
import 'package:apasbac_app/core/update/update_interceptor.dart';
import 'package:apasbac_app/core/update/update_manager.dart';
import 'package:apasbac_app/core/update/update_manifest.dart';
import 'package:apasbac_app/core/update/update_platform.dart';
import 'package:apasbac_app/core/update/update_repository.dart';
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> fixture(
        {int code = 12, int minimum = 8, bool mandatory = false}) =>
    {
      'schemaVersion': 1,
      'channel': 'stable',
      'versionCode': code,
      'versionName': '1.10.0',
      'minimumSupportedVersionCode': minimum,
      'mandatory': mandatory,
      'apkUrl':
          'https://github.com/APASBAC/apasbac-app/releases/download/v1.10.0/app-release.apk',
      'sha256': List.filled(64, 'a').join(),
      'sizeBytes': 100,
      'publishedAt': '2026-09-17T20:00:00Z',
      'releaseNotes': ['Correções'],
    };

Dio manifestHttp(Object? body, {int status = 200}) {
  final dio = Dio();
  dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
    if (status != 200) {
      h.reject(DioException(
          requestOptions: r,
          type: DioExceptionType.badResponse,
          response: Response(requestOptions: r, statusCode: status)));
    } else {
      h.resolve(Response(requestOptions: r, statusCode: status, data: body));
    }
  }));
  return dio;
}

class FakePlatform implements UpdatePlatform {
  int code = 11, downloads = 0, installs = 0;
  bool online = true, allowed = true, postponed = false;
  Map<String, dynamic> native = {'state': 'idle'};
  Completer<void>? downloadPending;
  @override
  Future<InstalledVersion> installedVersion() async =>
      InstalledVersion(code, '1.9.0', 'com.example.apasbac_app');
  @override
  Future<bool> isOnline() async => online;
  @override
  Future<Map<String, dynamic>> snapshot() async => native;
  @override
  Future<void> download(UpdateManifest manifest,
      {required bool mandatory}) async {
    downloads++;
    native = {'state': 'downloading', 'manifest': manifest.toJson()};
    await downloadPending?.future;
  }

  @override
  Future<void> cancel() async {
    native = {'state': 'updateAvailable'};
  }

  @override
  Future<void> install() async {
    if (!allowed) {
      native['state'] = 'needsUserPermission';
      return;
    }
    installs++;
    native['state'] = 'installing';
  }

  @override
  Future<void> requestInstallPermission() async {
    postponed = false;
    allowed = true;
  }

  @override
  Future<void> resume() async {
    if (native['state'] == 'needsUserPermission' && allowed && !postponed) {
      await install();
    }
  }

  @override
  Future<void> postpone() async {
    postponed = true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    UpdateRuntime.requiredVersion.value = 0;
  });
  test('versionCode governs equal, higher local and newer remote versions', () {
    final m = UpdateManifest.fromJson(fixture());
    expect(m.isNewerThan(12), false);
    expect(m.isNewerThan(13), false);
    expect(m.isNewerThan(11), true);
  });
  test('optional, mandatory and minimum supported version', () {
    expect(UpdateManifest.fromJson(fixture()).isRequiredFor(11), false);
    expect(UpdateManifest.fromJson(fixture(mandatory: true)).isRequiredFor(11),
        true);
    expect(UpdateManifest.fromJson(fixture()).isRequiredFor(7), true);
    expect(UpdateManifest.fromJson(fixture(mandatory: true)).isRequiredFor(12),
        false);
  });
  test('unknown fields are ignored', () {
    expect(
        UpdateManifest.fromJson({
          ...fixture(),
          'futureField': {'any': 'value'}
        }).versionCode,
        12);
  });
  for (final entry in <String, Object?>{
    'versionCode': '12',
    'schemaVersion': 2,
    'minimumSupportedVersionCode': 13,
    'mandatory': 'false',
    'sha256': 'invalid',
    'sizeBytes': 0,
    'apkUrl': 'https://evil.example/file.apk',
    'publishedAt': 'invalid',
    'releaseNotes': [42],
    'channel': 'beta',
  }.entries) {
    test('reject invalid ${entry.key} before download', () {
      expect(
          () => UpdateManifest.fromJson({...fixture(), entry.key: entry.value}),
          throwsFormatException);
    });
  }
  test('valid response is cached and used offline', () async {
    final repository =
        UpdateRepository(http: manifestHttp(jsonEncode(fixture())));
    expect((await repository.fetch(online: true)).manifest?.versionCode, 12);
    final offline = await repository.fetch(online: false);
    expect(offline.offline, true);
    expect(offline.manifest?.versionCode, 12);
  });
  for (final status in [404, 500]) {
    test('HTTP $status never forces unsupported assumptions without cache',
        () async {
      final result =
          await UpdateRepository(http: manifestHttp(null, status: status))
              .fetch(online: true);
      expect(result.manifest, isNull);
      expect(result.offline, true);
    });
  }
  test('invalid JSON cannot become a manifest', () async {
    expect(
        (await UpdateRepository(http: manifestHttp('{bad')).fetch(online: true))
            .manifest,
        isNull);
  });
  test('DNS and timeout errors use valid cache', () async {
    await UpdateRepository(http: manifestHttp(jsonEncode(fixture())))
        .fetch(online: true);
    for (final type in [
      DioExceptionType.connectionError,
      DioExceptionType.connectionTimeout
    ]) {
      final dio = Dio()
        ..interceptors.add(InterceptorsWrapper(
            onRequest: (r, h) =>
                h.reject(DioException(requestOptions: r, type: type))));
      expect(
          (await UpdateRepository(http: dio).fetch(online: true))
              .manifest
              ?.versionCode,
          12);
    }
  });
  test('CDN regression cannot remove a known minimum', () async {
    await UpdateRepository(http: manifestHttp(jsonEncode(fixture())))
        .fetch(online: true);
    final stale = await UpdateRepository(
            http: manifestHttp(jsonEncode(fixture(code: 11, minimum: 1))))
        .fetch(online: true);
    expect(stale.manifest?.versionCode, 12);
  });

  Future<UpdateManager> manager(FakePlatform platform,
      {Map<String, dynamic>? remote}) async {
    final m = UpdateManager(
        platform: platform,
        repository: UpdateRepository(
            http: manifestHttp(jsonEncode(remote ?? fixture()))));
    addTearDown(m.dispose);
    await m.start();
    return m;
  }

  test('optional dismissal survives navigation and does not auto-download',
      () async {
    final p = FakePlatform();
    final m = await manager(p);
    expect(m.visible, true);
    m.later();
    await m.check();
    expect(m.visible, false);
    expect(p.downloads, 0);
  });
  test('supported offline startup allows normal use', () async {
    final m = await manager(FakePlatform()..online = false);
    expect(m.visible, false);
    expect(m.mandatory, false);
  });
  test('cached unsupported offline startup blocks main features', () async {
    await UpdateRepository(http: manifestHttp(jsonEncode(fixture(minimum: 12))))
        .fetch(online: true);
    final m = await manager(FakePlatform()..online = false);
    expect(m.mandatory, true);
    expect(m.message, contains('Conecte-se'));
    m.later();
    expect(m.visible, true);
  });
  test('concurrent taps cannot enqueue two downloads', () async {
    final p = FakePlatform()..downloadPending = Completer<void>();
    final m = await manager(p);
    final first = m.download();
    await m.download();
    expect(p.downloads, 1);
    p.downloadPending!.complete();
    await first;
  });
  test('cancel then explicitly restart optional download', () async {
    final p = FakePlatform();
    final m = await manager(p);
    await m.download();
    await m.cancel();
    expect(m.dismissed, true);
    await m.download();
    expect(p.downloads, 2);
  });
  test(
      'permission is requested only after verification and resumes installation',
      () async {
    final p = FakePlatform()..allowed = false;
    final m = await manager(p);
    await m.download();
    p.native['state'] = 'readyToInstall';
    await m.poll();
    await m.poll();
    expect(m.state, UpdateState.needsUserPermission);
    expect(p.installs, 0);
    await m.grantPermission();
    await m.resume();
    expect(p.installs, 1);
  });
  test('pending Android confirmation never creates another session', () async {
    final p = FakePlatform();
    final m = await manager(p);
    await m.download();
    p.native['state'] = 'readyToInstall';
    await m.poll();
    p.native['message'] = 'Confirme a atualização na tela do Android.';
    await m.poll();
    await m.resume();
    await m.install();
    expect(p.installs, 1);
    expect(m.state, UpdateState.installing);
  });
  test('failed installation never retries automatically', () async {
    final p = FakePlatform();
    final m = await manager(p);
    await m.download();
    p.native.addAll({'state': 'failed', 'failures': 3});
    await m.poll();
    await m.resume();
    expect(m.state, UpdateState.failed);
    expect(m.failures, 3);
    expect(p.downloads, 1);
  });
  test('API 426 adds version headers and triggers mandatory flow', () async {
    final p = FakePlatform();
    final m = await manager(p);
    final dio = Dio()
      ..interceptors.add(AppVersionInterceptor(version: p.installedVersion));
    dio.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      expect(r.headers['X-App-Version-Code'], '11');
      expect(r.headers['X-App-Version-Name'], '1.9.0');
      expect(r.headers['X-App-Platform'], 'android');
      h.reject(
          DioException(
              requestOptions: r,
              response: Response(requestOptions: r, statusCode: 426, data: {
                'error': 'APP_UPDATE_REQUIRED',
                'minimumSupportedVersionCode': 12
              })),
          true);
    }));
    await expectLater(
        dio.get('https://api.test/protected'), throwsA(isA<DioException>()));
    await Future<void>.delayed(Duration.zero);
    expect(m.mandatory, true);
    expect(m.visible, true);
  });
  test('telemetry failure cannot hide an available update', () async {
    final m = UpdateManager(
        platform: FakePlatform(),
        repository: UpdateRepository(http: manifestHttp(jsonEncode(fixture()))),
        onEvent: (_, __, ___) => throw StateError('telemetry unavailable'),
        drainTelemetry: () => throw StateError('telemetry unavailable'));
    addTearDown(m.dispose);
    await m.start();
    expect(m.state, UpdateState.updateAvailable);
    expect(m.visible, true);
  });
  test('a new release replaces a failed old attempt', () async {
    final p = FakePlatform()
      ..native = {'state': 'failed', 'manifest': fixture(), 'failures': 3};
    final m = await manager(p, remote: fixture(code: 13));
    expect(m.manifest?.versionCode, 13);
    await m.retry();
    expect((p.native['manifest'] as Map)['versionCode'], 13);
    expect(p.downloads, 1);
  });
  test('Depois revokes permission-resume intent for an optional update',
      () async {
    final p = FakePlatform()..allowed = false;
    final m = await manager(p);
    await m.download();
    p.native['state'] = 'readyToInstall';
    await m.poll();
    await m.poll();
    m.later();
    p.allowed = true;
    await m.resume();
    expect(p.installs, 0);
    expect(m.visible, false);
  });
}
