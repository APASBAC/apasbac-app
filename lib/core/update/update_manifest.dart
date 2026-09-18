/// Public configuration: never put credentials in a --dart-define.
abstract final class UpdateConfig {
  static const repository = String.fromEnvironment('UPDATE_REPOSITORY',
      defaultValue: 'APASBAC/apasbac-app');
  static const channel =
      String.fromEnvironment('UPDATE_CHANNEL', defaultValue: 'stable');
  static String get manifestUrl =>
      'https://raw.githubusercontent.com/$repository/source/update/${channel == 'stable' ? 'version.json' : '$channel/version.json'}';
}

class InstalledVersion {
  final int code;
  final String name;
  final String packageName;
  const InstalledVersion(this.code, this.name, this.packageName);
}

class UpdateManifest {
  final int schemaVersion, versionCode, minimumSupportedVersionCode, sizeBytes;
  final String channel, versionName, sha256;
  final Uri apkUrl;
  final bool mandatory;
  final DateTime publishedAt;
  final List<String> releaseNotes;

  const UpdateManifest._(
      {required this.schemaVersion,
      required this.channel,
      required this.versionCode,
      required this.versionName,
      required this.minimumSupportedVersionCode,
      required this.mandatory,
      required this.apkUrl,
      required this.sha256,
      required this.sizeBytes,
      required this.publishedAt,
      required this.releaseNotes});

  factory UpdateManifest.fromJson(
    Object? value, {
    String expectedChannel = UpdateConfig.channel,
    String repository = UpdateConfig.repository,
  }) {
    if (value is! Map<String, dynamic>) {
      throw const FormatException('Invalid manifest');
    }
    int integer(String key, int max) {
      final v = value[key];
      if (v is! int || v < 1 || v > max) throw FormatException('Invalid $key');
      return v;
    }

    String string(String key, int max) {
      final v = value[key];
      if (v is! String || v.trim().isEmpty || v.length > max) {
        throw FormatException('Invalid $key');
      }
      return v;
    }

    final schema = integer('schemaVersion', 1);
    final channel = string('channel', 20);
    final code = integer('versionCode', 2100000000);
    final minimum = integer('minimumSupportedVersionCode', code);
    final url = Uri.tryParse(string('apkUrl', 2048));
    final hash = string('sha256', 64).toLowerCase();
    final date = DateTime.tryParse(string('publishedAt', 40));
    final notes = value['releaseNotes'];
    if (channel != expectedChannel ||
        !['stable', 'beta'].contains(channel) ||
        value['mandatory'] is! bool ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        date == null ||
        !date.isUtc ||
        url == null ||
        url.scheme != 'https' ||
        url.host != 'github.com' ||
        url.userInfo.isNotEmpty ||
        url.hasPort ||
        url.hasQuery ||
        url.hasFragment ||
        !url.path.startsWith('/$repository/releases/download/') ||
        url.pathSegments.length != 6 ||
        !url.path.endsWith('.apk') ||
        notes is! List ||
        notes.length > 50 ||
        notes.any((n) => n is! String || n.length > 1000)) {
      throw const FormatException('Invalid manifest');
    }
    return UpdateManifest._(
        schemaVersion: schema,
        channel: channel,
        versionCode: code,
        versionName: string('versionName', 100),
        minimumSupportedVersionCode: minimum,
        mandatory: value['mandatory'] as bool,
        apkUrl: url,
        sha256: hash,
        sizeBytes: integer('sizeBytes', 1073741824),
        publishedAt: date,
        releaseNotes: List<String>.unmodifiable(notes));
  }

  bool isNewerThan(int installed) => versionCode > installed;
  bool isRequiredFor(int installed) =>
      isNewerThan(installed) &&
      (mandatory || installed < minimumSupportedVersionCode);

  Map<String, dynamic> toJson() => {
        'schemaVersion': schemaVersion,
        'channel': channel,
        'versionCode': versionCode,
        'versionName': versionName,
        'minimumSupportedVersionCode': minimumSupportedVersionCode,
        'mandatory': mandatory,
        'apkUrl': apkUrl.toString(),
        'sha256': sha256,
        'sizeBytes': sizeBytes,
        'publishedAt': publishedAt.toUtc().toIso8601String(),
        'releaseNotes': releaseNotes,
      };
}
