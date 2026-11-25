import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/services/monitoring_upload_queue.dart';
import '../../../../core/theme/semantic_colors.dart';
import '../../../../providers.dart';

/// Situação do envio em segundo plano de um monitoramento (se houver).
class UploadStatusCard extends ConsumerWidget {
  final String monitoringId;
  const UploadStatusCard({super.key, required this.monitoringId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final queue = ref.watch(uploadQueueProvider);
    final job = queue.jobFor(monitoringId);
    if (job == null) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    final failed = job.status == UploadStatus.failed;
    final waiting = job.status == UploadStatus.waitingNetwork;
    final color = failed ? SemanticColors.rejected : SemanticColors.review;
    final pct = (job.progress * 100).floor();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(
                failed
                    ? Icons.error_outline_rounded
                    : waiting
                        ? Icons.wifi_off_rounded
                        : Icons.cloud_upload_outlined,
                color: color),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                failed
                    ? 'O envio não foi concluído'
                    : waiting
                        ? 'Aguardando conexão para continuar'
                        : 'Enviando em segundo plano — $pct%',
                style: TextStyle(fontWeight: FontWeight.w700, color: color),
              ),
            ),
          ]),
          if (!failed) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: waiting ? null : job.progress,
              minHeight: 6,
              borderRadius: BorderRadius.circular(6),
              semanticsLabel: 'Progresso do envio',
            ),
            const SizedBox(height: 10),
            Text(
              'Pode sair do aplicativo: o envio continua e avisamos quando terminar.',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            ),
          ] else ...[
            const SizedBox(height: 8),
            Text(job.error ?? 'Tente novamente.',
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(spacing: 8, runSpacing: 8, children: [
              FilledButton.icon(
                onPressed: () => queue.retry(monitoringId),
                icon: const Icon(Icons.refresh_rounded),
                label: const Text('Tentar de novo'),
              ),
              OutlinedButton(
                onPressed: () => queue.cancel(monitoringId),
                child: const Text('Escolher arquivos de novo'),
              ),
            ]),
          ],
        ],
      ),
    );
  }
}
