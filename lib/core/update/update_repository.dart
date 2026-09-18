import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'update_manifest.dart';

class ManifestResult {
  final UpdateManifest? manifest;
  final bool offline;
  const ManifestResult(this.manifest, {this.offline = false});
}

class UpdateRepository {
  final Dio http;
  final Future<SharedPreferences> Function() preferences;
  UpdateRepository(
      {Dio? http, Future<SharedPreferences> Function()? preferences})
      : http = http ??
            Dio(BaseOptions(
                connectTimeout: const Duration(seconds: 8),
                receiveTimeout: const Duration(seconds: 8))),
        preferences = preferences ?? SharedPreferences.getInstance;
  String get _key => 'update_manifest_${UpdateConfig.channel}';

  Future<ManifestResult> fetch({required bool online}) async {
    final prefs = await preferences();
    UpdateManifest? cached;
    try {
      cached =
          UpdateManifest.fromJson(jsonDecode(prefs.getString(_key) ?? 'null'));
    } catch (_) {/* A damaged cache is never a download source. */}
    if (online) {
      try {
        final response = await http
            .get<String>(UpdateConfig.manifestUrl,
                queryParameters: {
                  't': DateTime.now().millisecondsSinceEpoch ~/ 300000
                },
                options: Options(
                    responseType: ResponseType.plain,
                    followRedirects: false,
                    headers: {'Cache-Control': 'no-cache'}))
            .timeout(const Duration(seconds: 10));
        final body = response.data;
        if (body == null || body.length > 65536) throw const FormatException();
        final remote = UpdateManifest.fromJson(jsonDecode(body));
        // CDN regression must not revive an older APK or remove a known minimum.
        if (cached != null &&
            (remote.versionCode < cached.versionCode ||
                remote.minimumSupportedVersionCode <
                    cached.minimumSupportedVersionCode)) {
          return ManifestResult(cached);
        }
        try {
          await prefs.setString(_key, jsonEncode(remote.toJson()));
        } catch (_) {}
        return ManifestResult(remote);
      } catch (_) {
        /* DNS, timeout, HTTP and invalid JSON use the last valid reply. */
      }
    }
    return ManifestResult(cached, offline: true);
  }

  Future<int> requiredMinimum() async =>
      (await preferences()).getInt('update_required_minimum') ?? 0;
  Future<void> rememberMinimum(int code) async {
    final prefs = await preferences();
    if (code > (prefs.getInt('update_required_minimum') ?? 0)) {
      await prefs.setInt('update_required_minimum', code);
    }
  }
}
