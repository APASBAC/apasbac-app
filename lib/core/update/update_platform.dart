import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'update_manifest.dart';

abstract class UpdatePlatform {
  Future<InstalledVersion> installedVersion();
  Future<bool> isOnline();
  Future<Map<String, dynamic>> snapshot();
  Future<void> download(UpdateManifest manifest, {required bool mandatory});
  Future<void> cancel();
  Future<void> install();
  Future<void> requestInstallPermission();
  Future<void> resume();
  Future<void> postpone() async {}
}

class AndroidUpdatePlatform implements UpdatePlatform {
  static const _channel = MethodChannel('org.apasbac/app_update');
  @override
  Future<InstalledVersion> installedVersion() async {
    final info =
        (await _channel.invokeMapMethod<String, dynamic>('installedVersion'))!;
    return InstalledVersion(info['code'] as int, info['name'] as String,
        info['packageName'] as String);
  }

  @override
  Future<bool> isOnline() async =>
      await _channel.invokeMethod<bool>('isOnline') ?? false;
  @override
  Future<Map<String, dynamic>> snapshot() async => Map<String, dynamic>.from(
      await _channel.invokeMapMethod('snapshot') ?? {});
  @override
  Future<void> download(UpdateManifest manifest, {required bool mandatory}) =>
      _channel.invokeMethod('download',
          {'manifest': jsonEncode(manifest.toJson()), 'mandatory': mandatory});
  @override
  Future<void> cancel() => _channel.invokeMethod('cancel');
  @override
  Future<void> install() => _channel.invokeMethod('install');
  @override
  Future<void> requestInstallPermission() =>
      _channel.invokeMethod('requestInstallPermission');
  @override
  Future<void> resume() => _channel.invokeMethod('resume');
  @override
  Future<void> postpone() => _channel.invokeMethod('postpone');
}

/// Decouples HTTP authentication from the UI and update transport.
abstract final class UpdateRuntime {
  static final requiredVersion = ValueNotifier<int>(0);
  static Future<InstalledVersion?>? _version;
  static Future<InstalledVersion?> get version => _version ??= _readVersion();
  static Future<InstalledVersion?> _readVersion() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return null;
    try {
      return await AndroidUpdatePlatform().installedVersion();
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }

  static void require(int minimum) {
    if (minimum > requiredVersion.value) requiredVersion.value = minimum;
  }
}
