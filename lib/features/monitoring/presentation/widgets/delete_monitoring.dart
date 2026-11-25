import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/models/monitoring_model.dart';
import '../../../../core/utils/friendly_error.dart';
import '../../../../providers.dart';

/// Confirma e apaga um monitoramento (somente Admin). Retorna true se apagou.
Future<bool> confirmAndDeleteMonitoring(
    BuildContext context, WidgetRef ref, MonitoringModel monitoring) async {
  final animal = monitoring.animal?.name ?? 'Animal #${monitoring.animalId}';
  final tutor = monitoring.tutorName ?? monitoring.animal?.adopterName;
  final hasMedia = monitoring.medias.isNotEmpty;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return AlertDialog(
        icon: Icon(Icons.delete_forever_rounded, color: cs.error, size: 32),
        title: const Text('Apagar monitoramento?'),
        content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$animal${tutor != null ? ' • $tutor' : ''}',
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 10),
              Text(hasMedia
                  ? 'O monitoramento, as fotos e o vídeo enviados serão apagados para sempre.'
                  : 'O monitoramento será apagado para sempre.'),
              const SizedBox(height: 6),
              Text('Essa ação não pode ser desfeita.',
                  style: TextStyle(color: cs.onSurfaceVariant)),
            ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton.icon(
            style: FilledButton.styleFrom(
                backgroundColor: cs.error, foregroundColor: cs.onError),
            onPressed: () => Navigator.pop(context, true),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Apagar'),
          ),
        ],
      );
    },
  );
  if (confirmed != true || !context.mounted) return false;

  final messenger = ScaffoldMessenger.of(context);
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const PopScope(
      canPop: false,
      child: AlertDialog(
        content: Row(children: [
          SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2.5)),
          SizedBox(width: 16),
          Expanded(child: Text('Apagando monitoramento…')),
        ]),
      ),
    ),
  );
  try {
    await ref.read(monitoringServiceProvider).deleteMonitoring(monitoring.id);
    await ref.read(uploadQueueProvider).cancel(monitoring.id);
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    ref.invalidate(myMonitoringsProvider);
    ref.invalidate(monitoringDetailProvider(monitoring.id));
    messenger.showSnackBar(
        SnackBar(content: Text('Monitoramento de $animal apagado.')));
    return true;
  } catch (e) {
    if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    messenger.showSnackBar(SnackBar(
        content: Text('Não foi possível apagar. ${friendlyMessage(e)}')));
    return false;
  }
}
