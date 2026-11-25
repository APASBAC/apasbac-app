import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'router.dart';
import 'providers.dart';
import 'core/models/monitoring_model.dart';
import 'core/notifications/monitoring_reminders.dart';
import 'core/notifications/upload_notifications.dart';
import 'core/services/monitoring_upload_queue.dart';
import 'core/theme/app_theme.dart';
import 'core/update/update_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await MonitoringReminders.init();
  MonitoringUploadQueue.instance.notifier = AndroidUploadNotifier();
  runApp(const ProviderScope(child: ApasbacApp()));
}

class ApasbacApp extends ConsumerWidget {
  const ApasbacApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    MonitoringReminders.onOpen = (id) => router.push('/home/monitoring/$id');
    final queue = ref.read(uploadQueueProvider);
    queue.onFinished = (id) {
      ref.invalidate(monitoringDetailProvider(id));
      ref.invalidate(myMonitoringsProvider);
    };

    // Mantém os lembretes do tutor em dia sempre que os monitoramentos carregam.
    ref.listen<AsyncValue<List<MonitoringModel>>>(myMonitoringsProvider,
        (_, next) {
      final user = ref.read(authProvider).valueOrNull;
      if (user == null) {
        MonitoringReminders.clear();
        return;
      }
      final items = next.valueOrNull;
      if (items == null) return;
      // Retoma envios interrompidos (app fechado ou sem internet).
      queue.resume();
      if (user.isTutor) MonitoringReminders.sync(items);
      MonitoringReminders.consumePendingOpen();
    });

    return MaterialApp.router(
      title: 'APASBAC',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      routerConfig: router,
      builder: (context, child) =>
          UpdateGate(child: child ?? const SizedBox.shrink()),
    );
  }
}
