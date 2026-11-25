import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

import '../models/monitoring_model.dart';

/// Um lembrete agendado para um monitoramento.
class ReminderPlan {
  final int id;
  final String monitoringId;
  final DateTime when;
  final String title, body;
  const ReminderPlan(
      this.id, this.monitoringId, this.when, this.title, this.body);
}

/// Lembretes locais (no próprio celular) para o tutor enviar o monitoramento:
/// 3 dias antes do prazo, 1 dia antes, no dia e, se atrasar, 1 e 3 dias depois.
/// Funcionam sem internet e são reagendados sempre que a lista é carregada.
class MonitoringReminders {
  MonitoringReminders._();

  static const hour = 9; // horário dos lembretes
  static const _channel = AndroidNotificationDetails(
    'monitoring_reminders',
    'Lembretes de monitoramento',
    channelDescription: 'Avisos sobre o prazo para enviar fotos e vídeo.',
    importance: Importance.high,
    priority: Priority.high,
    color: Color(0xFF8B1A1A),
  );

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;
  static bool _asked = false;
  static String? _pendingOpen;

  /// Chamado ao tocar numa notificação (recebe o id do monitoramento).
  static void Function(String monitoringId)? onOpen;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  static Future<void> init() async {
    tzdata.initializeTimeZones();
    try {
      tz.setLocalLocation(tz.getLocation('America/Sao_Paulo'));
    } catch (_) {}
    if (!_supported) return;
    try {
      await _plugin.initialize(
        settings: const InitializationSettings(
            android: AndroidInitializationSettings('ic_stat_paw')),
        onDidReceiveNotificationResponse: (r) => _open(r.payload),
      );
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp == true) {
        _pendingOpen = launch!.notificationResponse?.payload;
      }
      _ready = true;
    } catch (e) {
      debugPrint('[MonitoringReminders] indisponível: $e');
    }
  }

  static void _open(String? id) {
    if (id == null || id.isEmpty) return;
    final handler = onOpen;
    if (handler == null) {
      _pendingOpen = id;
    } else {
      handler(id);
    }
  }

  /// Abre o monitoramento da notificação que iniciou o app, se houver.
  static void consumePendingOpen() {
    final id = _pendingOpen;
    _pendingOpen = null;
    if (id != null) _open(id);
  }

  /// Calcula os lembretes futuros (função pura, testável).
  static List<ReminderPlan> plan(List<MonitoringModel> items, DateTime now) {
    final plans = <ReminderPlan>[];
    for (final m in items) {
      final due = m.dueDate?.toLocal();
      if (!m.canSubmit || due == null) continue;
      final name =
          m.animal?.name.isNotEmpty == true ? m.animal!.name : 'seu animal';
      final title = 'Monitoramento de $name';
      final steps = <(int, String)>[
        (-3, 'Faltam 3 dias para enviar as fotos e o vídeo de $name.'),
        (-1, 'Amanhã é o último dia para enviar o monitoramento de $name.'),
        (0, 'Hoje é o prazo para enviar o monitoramento de $name.'),
        (
          1,
          'O monitoramento de $name está atrasado. Envie as fotos e o vídeo assim que puder.'
        ),
        (
          3,
          'O monitoramento de $name continua pendente. Envie para manter o acompanhamento em dia.'
        ),
      ];
      final base = (m.id.hashCode & 0x7FFFFFFF) % 100000000 * 10;
      for (var i = 0; i < steps.length; i++) {
        final day = DateTime(due.year, due.month, due.day + steps[i].$1, hour);
        if (day.isAfter(now)) {
          plans.add(ReminderPlan(
              (base + i) & 0x7FFFFFFF, m.id, day, title, steps[i].$2));
        }
      }
    }
    return plans;
  }

  /// Substitui os lembretes agendados pelos da lista atual do tutor.
  static Future<void> sync(List<MonitoringModel> items) async {
    if (!_ready) return;
    try {
      final plans = plan(items, DateTime.now());
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      if (plans.isNotEmpty && !_asked) {
        _asked = true;
        await android?.requestNotificationsPermission();
      }
      for (final p in await _plugin.pendingNotificationRequests()) {
        await _plugin.cancel(id: p.id);
      }
      for (final p in plans) {
        await _plugin.zonedSchedule(
          id: p.id,
          title: p.title,
          body: p.body,
          scheduledDate: tz.TZDateTime.from(p.when, tz.local),
          notificationDetails: const NotificationDetails(android: _channel),
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          payload: p.monitoringId,
        );
      }
      debugPrint(
          '[MonitoringReminders] ${plans.length} lembrete(s) agendado(s)');
    } catch (e) {
      debugPrint('[MonitoringReminders] falha ao agendar: $e');
    }
  }

  /// Remove os lembretes (ex.: ao sair da conta).
  static Future<void> clear() async {
    if (!_ready) return;
    try {
      for (final p in await _plugin.pendingNotificationRequests()) {
        await _plugin.cancel(id: p.id);
      }
    } catch (_) {}
  }
}
