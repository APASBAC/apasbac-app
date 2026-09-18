import 'package:dio/dio.dart';
import 'update_manifest.dart';
import 'update_platform.dart';

class AppUpdateRequired implements Exception {
  @override
  String toString() => 'Esta versão precisa ser atualizada.';
}

class AppVersionInterceptor extends Interceptor {
  final Future<InstalledVersion?> Function() version;
  final void Function(int) onRequired;
  AppVersionInterceptor(
      {Future<InstalledVersion?> Function()? version,
      void Function(int)? onRequired})
      : version = version ?? (() => UpdateRuntime.version),
        onRequired = onRequired ?? UpdateRuntime.require;

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final installed = await version();
    if (installed != null) {
      options.headers.addAll({
        'X-App-Version-Code': installed.code.toString(),
        'X-App-Version-Name': installed.name,
        'X-App-Platform': 'android'
      });
    }
    handler.next(options);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) {
    final data = err.response?.data;
    if (err.response?.statusCode == 426 &&
        data is Map &&
        data['error'] == 'APP_UPDATE_REQUIRED') {
      final min = data['minimumSupportedVersionCode'];
      if (min is int && min > 0 && min <= 2100000000) onRequired(min);
      handler.next(err.copyWith(
          error: AppUpdateRequired(),
          message: 'Esta versão precisa ser atualizada.'));
      return;
    }
    handler.next(err);
  }
}
