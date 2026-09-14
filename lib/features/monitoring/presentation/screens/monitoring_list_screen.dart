import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../../../providers.dart';
import '../../../../core/models/monitoring_model.dart';

class MonitoringListScreen extends ConsumerWidget {
  const MonitoringListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final userAsync = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Monitoramentos'),
        leading: BackButton(onPressed: () => context.go('/home')),
      ),
      body: userAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => const Center(child: Text('Erro ao carregar usuário')),
        data: (user) {
          // Usuário não é tutor — exibe aviso sem fazer request
          if (user == null || !user.canAccessMonitoring) {
            return _NotTutorView();
          }
          return _MonitoringList();
        },
      ),
    );
  }
}

// ── Aviso de não-tutor ────────────────────────────────────────

class _NotTutorView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.person_off_outlined,
                  size: 56, color: Colors.orange.shade400),
            ),
            const SizedBox(height: 24),
            const Text(
              'Você ainda não é um tutor',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            Text(
              'O acesso aos monitoramentos é exclusivo para tutores — pessoas que adotaram um animal pela APASBAC.',
              style: TextStyle(
                fontSize: 14,
                color: cs.onSurfaceVariant,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest.withOpacity(0.5),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.info_outline, size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Se você já adotou um animal e seu cadastro ainda não foi atualizado, entre em contato com a equipe da APASBAC.',
                      style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant, height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Lista de monitoramentos ───────────────────────────────────

class _MonitoringList extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitoringsAsync = ref.watch(myMonitoringsProvider);
    final user = ref.watch(authProvider).valueOrNull;

    return monitoringsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (err, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 60, color: Colors.red),
              const SizedBox(height: 16),
              Text(err.toString(), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => ref.invalidate(myMonitoringsProvider),
                child: const Text('Tentar novamente'),
              ),
            ],
          ),
        ),
      ),
      data: (monitorings) {
        if (monitorings.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.monitor_heart_outlined,
                    size: 80, color: Colors.grey.shade300),
                const SizedBox(height: 16),
                const Text('Nenhum monitoramento encontrado',
                    style: TextStyle(fontSize: 16, color: Colors.grey)),
              ],
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myMonitoringsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: monitorings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _MonitoringCard(
              monitoring: monitorings[i],
              canSubmit: user?.isTutor == true && monitorings[i].canSubmit,
            ),
          ),
        );
      },
    );
  }
}

// ── Card de monitoramento ─────────────────────────────────────

class _MonitoringCard extends StatelessWidget {
  final MonitoringModel monitoring;
  final bool canSubmit;
  const _MonitoringCard({
    required this.monitoring,
    required this.canSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final statusColor = _statusColor(monitoring.status);

    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push('/home/monitoring/${monitoring.id}'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_statusIcon(monitoring.status),
                        color: statusColor, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          monitoring.animal?.name ?? 'Animal #${monitoring.animalId}',
                          style: const TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold),
                        ),
                        if (monitoring.animal?.breed != null)
                          Text(monitoring.animal!.breed,
                              style: TextStyle(
                                  fontSize: 12, color: cs.onSurfaceVariant)),
                      ],
                    ),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: statusColor.withOpacity(0.4)),
                    ),
                    child: Text(
                      monitoring.statusLabel,
                      style: TextStyle(
                          fontSize: 11,
                          color: statusColor,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              if (monitoring.notes != null) ...[
                const SizedBox(height: 10),
                Text(
                  monitoring.notes!,
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (monitoring.createdAt != null) ...[
                    Icon(Icons.calendar_today_outlined,
                        size: 13, color: cs.onSurfaceVariant),
                    const SizedBox(width: 4),
                    Text(
                      DateFormat('dd/MM/yyyy').format(monitoring.createdAt!),
                      style:
                          TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ],
                  const Spacer(),
                  if (canSubmit)
                    TextButton.icon(
                      onPressed: () => context
                          .push('/home/monitoring/${monitoring.id}/submit'),
                      icon: const Icon(Icons.upload_rounded, size: 16),
                      label: const Text('Enviar'),
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _statusColor(String status) => switch (status) {
        'PENDING' => Colors.orange,
        'IN_REVIEW' => Colors.blue,
        'APPROVED' => Colors.green,
        'REJECTED' => Colors.red,
        _ => Colors.grey,
      };

  IconData _statusIcon(String status) => switch (status) {
        'PENDING' => Icons.hourglass_empty_rounded,
        'IN_REVIEW' => Icons.manage_search_rounded,
        'APPROVED' => Icons.check_circle_outline_rounded,
        'REJECTED' => Icons.cancel_outlined,
        _ => Icons.help_outline_rounded,
      };
}
