import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../services/monitoring_upload_queue.dart';

/// Notificações do envio de monitoramento. Enquanto envia, um serviço em
/// primeiro plano (tipo dataSync) mantém o app ativo mesmo fora da tela.
class AndroidUploadNotifier implements UploadNotifier {
  AndroidUploadNotifier([FlutterLocalNotificationsPlugin? plugin])
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  static const _serviceId = 7402;
  static const _resultId = 7403;
  static const _color = Color(0xFF8B1A1A);

  final FlutterLocalNotificationsPlugin _plugin;
  bool _serviceOn = false;

  AndroidFlutterLocalNotificationsPlugin? get _android => kIsWeb
      ? null
      : _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  String _name(UploadJob job) =>
      job.animalName.isEmpty ? 'seu animal' : job.animalName;

  Future<void> _foreground(UploadJob job, String body,
      {bool indeterminate = false}) async {
    final android = _android;
    if (android == null) return;
    final pct = (job.progress * 100).clamp(0, 100).round();
    try {
      await android.startForegroundService(
        id: _serviceId,
        title: 'Enviando monitoramento de ${_name(job)}',
        body: body,
        payload: job.monitoringId,
        foregroundServiceTypes: {
          AndroidServiceForegroundType.foregroundServiceTypeDataSync
        },
        notificationDetails: AndroidNotificationDetails(
          'monitoring_upload',
          'Envio de monitoramento',
          channelDescription: 'Progresso do envio das fotos e do vídeo.',
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showProgress: true,
          maxProgress: 100,
          progress: pct,
          indeterminate: indeterminate,
          color: _color,
          icon: '@mipmap/ic_launcher',
        ),
      );
      _serviceOn = true;
    } catch (e) {
      debugPrint('[UploadNotifier] serviço indisponível: $e');
    }
  }

  @override
  Future<void> progress(UploadJob job) => _foreground(job,
      '${(job.progress * 100).floor()}% — pode sair do app, o envio continua.');

  @override
  Future<void> waiting(UploadJob job) =>
      _foreground(job, 'Sem conexão. Tentando de novo em instantes…',
          indeterminate: true);

  @override
  Future<void> stop() async {
    if (!_serviceOn) return;
    _serviceOn = false;
    try {
      await _android?.stopForegroundService();
    } catch (_) {}
  }

  Future<void> _result(UploadJob job, String title, String body) async {
    try {
      await _plugin.show(
        id: _resultId,
        title: title,
        body: body,
        payload: job.monitoringId,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            'monitoring_upload_result',
            'Resultado do envio de monitoramento',
            channelDescription: 'Aviso quando o envio termina ou falha.',
            importance: Importance.high,
            priority: Priority.high,
            color: _color,
          ),
        ),
      );
    } catch (_) {}
  }

  @override
  Future<void> done(UploadJob job) => _result(job, 'Monitoramento enviado',
      'As fotos e o vídeo de ${_name(job)} chegaram à APASBAC. Obrigado!');

  @override
  Future<void> failed(UploadJob job) => _result(
      job,
      'Não foi possível enviar o monitoramento',
      '${job.error ?? 'Tente novamente.'} Toque para abrir e tentar de novo.');
}
