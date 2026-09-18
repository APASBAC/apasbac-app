import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'update_manifest.dart';
import 'update_platform.dart';
import 'update_repository.dart';

enum UpdateState {
  idle,
  checking,
  upToDate,
  updateAvailable,
  downloading,
  verifying,
  readyToInstall,
  installing,
  needsUserPermission,
  failed
}

class UpdateManager extends ChangeNotifier {
  final UpdateRepository repository;
  final UpdatePlatform platform;
  final void Function(String, int, int)? onEvent;
  final void Function()? drainTelemetry;
  final Set<int> _announced = {};
  UpdateManager(
      {required this.repository,
      required this.platform,
      this.onEvent,
      this.drainTelemetry});
  UpdateState state = UpdateState.idle;
  InstalledVersion? installed;
  UpdateManifest? manifest;
  String? message;
  bool mandatory = false, dismissed = false, offline = false;
  int downloaded = 0, failures = 0;
  bool _checking = false, _action = false, _polling = false, _disposed = false;
  bool _foreground = true, _started = false;
  int _serverMinimum = 0;
  Timer? _timer;
  DateTime? _lastCheck;
  bool get busy =>
      _action ||
      {UpdateState.downloading, UpdateState.verifying, UpdateState.installing}
          .contains(state);
  bool get visible =>
      mandatory ||
      (!dismissed &&
          manifest != null &&
          state != UpdateState.upToDate &&
          state != UpdateState.checking &&
          state != UpdateState.idle);
  bool get canPostpone =>
      !mandatory &&
      !busy &&
      {
        UpdateState.updateAvailable,
        UpdateState.failed,
        UpdateState.needsUserPermission
      }.contains(state);

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  void _drain() {
    try {
      drainTelemetry?.call();
    } catch (_) {}
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    UpdateRuntime.requiredVersion.addListener(_apiRequired);
    try {
      installed = await platform.installedVersion();
      _serverMinimum = await repository.requiredMinimum();
      final cached = await repository.fetch(online: false);
      manifest = cached.manifest;
      mandatory = installed!.code < _serverMinimum ||
          (manifest?.isRequiredFor(installed!.code) ?? false);
      if (mandatory) {
        state = UpdateState.checking;
        _emit();
      }
      _apiRequired();
      await platform.resume();
      _drain();
      await check();
      _timer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (_foreground) unawaited(poll());
      });
    } on MissingPluginException {
      state = UpdateState.idle;
    } catch (_) {
      state = UpdateState.idle;
    }
    _emit();
  }

  void _apiRequired() {
    final minimum = UpdateRuntime.requiredVersion.value;
    if (minimum <= _serverMinimum) return;
    _serverMinimum = minimum;
    unawaited(repository.rememberMinimum(minimum).catchError((_) {}));
    if (installed != null && installed!.code < minimum) {
      mandatory = true;
      dismissed = false;
      message = 'Esta versão precisa ser atualizada.';
      _emit();
      unawaited(check(force: true));
    }
  }

  Future<void> check({bool force = false}) async {
    if (_checking || busy || installed == null) return;
    if (!force &&
        _lastCheck != null &&
        DateTime.now().difference(_lastCheck!) < const Duration(minutes: 5)) {
      return;
    }
    _checking = true;
    _lastCheck = DateTime.now();
    mandatory = mandatory || installed!.code < _serverMinimum;
    state = UpdateState.checking;
    _emit();
    try {
      bool online;
      try {
        online = await platform.isOnline();
      } catch (_) {
        online = false;
      }
      final result = await repository.fetch(online: online);
      offline = result.offline;
      manifest = result.manifest;
      final m = manifest;
      mandatory = installed!.code < _serverMinimum ||
          (m?.isRequiredFor(installed!.code) ?? false);
      if (kDebugMode) {
        debugPrint(
            'UpdateCheck: installedCode=${installed!.code} remoteCode=${m?.versionCode} update=${m?.isNewerThan(installed!.code) ?? false}');
      }
      if (m != null && m.isNewerThan(installed!.code)) {
        state = UpdateState.updateAvailable;
        if (_announced.add(m.versionCode)) {
          try {
            onEvent?.call('update_available', installed!.code, m.versionCode);
          } catch (_) {}
        }
        message = offline && mandatory
            ? 'Esta versão precisa ser atualizada. Conecte-se à internet para continuar.'
            : null;
      } else if (mandatory) {
        state = UpdateState.failed;
        message = offline
            ? 'Esta versão precisa ser atualizada. Conecte-se à internet para continuar.'
            : 'A atualização necessária ainda não está disponível. Tente novamente em instantes.';
      } else {
        state = m == null ? UpdateState.idle : UpdateState.upToDate;
        message = null;
      }
      await poll();
    } catch (_) {
      state = mandatory ? UpdateState.failed : UpdateState.idle;
      message =
          'Esta versão precisa ser atualizada. Conecte-se à internet para continuar.';
    } finally {
      _checking = false;
      _emit();
    }
  }

  Future<void> poll() async {
    if (_polling || installed == null || _disposed) return;
    _polling = true;
    try {
      final snapshot = await platform.snapshot();
      if (snapshot['manifest'] is Map) {
        final native = UpdateManifest.fromJson(
            Map<String, dynamic>.from(snapshot['manifest'] as Map));
        if (native.versionCode <= installed!.code) return;
        if (manifest != null &&
            native.versionCode < manifest!.versionCode &&
            {'failed', 'updateAvailable', 'idle'}.contains(snapshot['state'])) {
          return;
        }
        // Finish an already approved release; the next check can discover a newer one.
        if (snapshot['state'] != 'idle') manifest = native;
      }
      if (manifest == null || !manifest!.isNewerThan(installed!.code)) return;
      mandatory = mandatory || manifest!.isRequiredFor(installed!.code);
      final nativeState = snapshot['state'];
      if (nativeState == 'idle' || nativeState == null) return;
      final previous = state;
      state = UpdateState.values.firstWhere((s) => s.name == nativeState,
          orElse: () => UpdateState.failed);
      downloaded = (snapshot['downloaded'] as num?)?.toInt() ?? 0;
      failures = (snapshot['failures'] as num?)?.toInt() ?? 0;
      message = snapshot['message'] as String?;
      if (previous != state) _drain();
      _emit();
      if (state == UpdateState.readyToInstall && _foreground && !_action) {
        await install();
      }
    } catch (_) {
      /* Polling failure never starts another download or installation. */
    } finally {
      _polling = false;
    }
  }

  Future<void> download() async {
    if (busy ||
        _checking ||
        manifest == null ||
        !manifest!.isNewerThan(installed!.code)) {
      return;
    }
    _action = true;
    dismissed = false;
    state = UpdateState.downloading;
    message = null;
    _emit();
    try {
      await platform.download(manifest!, mandatory: mandatory);
    } catch (_) {
      state = UpdateState.failed;
      message = 'Não foi possível iniciar a atualização. Tente novamente.';
    } finally {
      _action = false;
      _emit();
    }
    await poll();
  }

  Future<void> install() async {
    if (_action || state != UpdateState.readyToInstall) return;
    _action = true;
    state = UpdateState.installing;
    _emit();
    try {
      await platform.install();
    } catch (_) {
      state = UpdateState.failed;
      message = 'Não foi possível instalar. Tente novamente.';
    } finally {
      _action = false;
      _emit();
    }
  }

  Future<void> grantPermission() async {
    if (_action) return;
    _action = true;
    try {
      await platform.requestInstallPermission();
    } catch (_) {
      message =
          'Não foi possível abrir a autorização de instalação. Tente novamente.';
    } finally {
      _action = false;
      _emit();
    }
  }

  Future<void> retry() async {
    if (busy || _checking) return;
    // Always refresh the policy after a failed attempt; retries require a tap.
    await check(force: true);
    if (manifest != null && manifest!.isNewerThan(installed!.code) && !busy) {
      await download();
    }
  }

  Future<void> cancel() async {
    if (mandatory || _action || state != UpdateState.downloading) return;
    await platform.cancel();
    state = UpdateState.updateAvailable;
    dismissed = true;
    _emit();
  }

  void later() {
    if (canPostpone) {
      dismissed = true;
      unawaited(platform.postpone().catchError((_) {}));
      _emit();
    }
  }

  void background() {
    _foreground = false;
  }

  Future<void> resume() async {
    _foreground = true;
    try {
      await platform.resume();
      await poll();
    } catch (_) {}
  }

  @override
  void dispose() {
    _disposed = true;
    _timer?.cancel();
    UpdateRuntime.requiredVersion.removeListener(_apiRequired);
    super.dispose();
  }
}
