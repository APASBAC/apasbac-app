import 'package:dio/dio.dart';
import 'package:flutter/services.dart';
import '../api/api_client.dart';

/// Best effort only. Failures are swallowed and never feed the update state machine.
class UpdateTelemetry {
  bool _draining = false;
  final ApiClient client;
  UpdateTelemetry({ApiClient? client}) : client = client ?? ApiClient();
  Future<void> send(String event, int installed, int target) async {
    try {
      if (await client.getAccessToken() == null) return;
      await client.dio
          .post('/app/update-events',
              data: {
                'event': event,
                'installedVersionCode': installed,
                'targetVersionCode': target,
              },
              options: Options(
                  sendTimeout: const Duration(seconds: 3),
                  receiveTimeout: const Duration(seconds: 3)))
          .timeout(const Duration(seconds: 4));
    } catch (_) {}
  }

  Future<void> drain() async {
    if (_draining) return;
    _draining = true;
    try {
      final events = await const MethodChannel('org.apasbac/app_update')
              .invokeListMethod('drainEvents') ??
          [];
      for (final e in events) {
        if (e is Map &&
            e['event'] is String &&
            e['installedVersionCode'] is int &&
            e['targetVersionCode'] is int) {
          await send(e['event'] as String, e['installedVersionCode'] as int,
              e['targetVersionCode'] as int);
        }
      }
    } catch (_) {
    } finally {
      _draining = false;
    }
  }
}
