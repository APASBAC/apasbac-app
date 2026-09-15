import '../../../../core/widgets/apasbac_loading.dart';
import '../../../../core/theme/semantic_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../core/models/animal_model.dart';
import '../../../../core/models/monitoring_model.dart';
import '../../../../core/models/user_model.dart';
import '../../../../providers.dart';
import 'admin_forms.dart';

class AdminScreen extends ConsumerWidget {
  const AdminScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;

    if (user == null || !user.isAdminOrStaff) {
      return Scaffold(
        appBar: AppBar(title: const Text('Administração')),
        body: const Center(child: Text('Acesso restrito à equipe APASBAC.')),
      );
    }

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administração'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'Validações'),
              Tab(
                  icon: Icon(Icons.volunteer_activism_outlined),
                  text: 'Adoções'),
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Usuários'),
              Tab(icon: Icon(Icons.settings_outlined), text: 'Configurações'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _CreationTab(
                label: 'Criar monitoramento',
                route: '/home/admin/monitoring/new',
                child: _MonitoringReviewTab()),
            _CreationTab(
                label: 'Cadastrar animal',
                route: '/home/admin/animal/new',
                child: _AdoptionsTab()),
            _UsersTab(),
            ConfigsTab(),
          ],
        ),
      ),
    );
  }
}

class _CreationTab extends StatelessWidget {
  final String label, route;
  final Widget child;
  const _CreationTab(
      {required this.label, required this.route, required this.child});
  @override
  Widget build(BuildContext context) => Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                  onPressed: () => context.push(route),
                  icon: const Icon(Icons.add),
                  label: Text(label)),
            )),
        Expanded(child: child),
      ]);
}

class _MonitoringReviewTab extends ConsumerWidget {
  const _MonitoringReviewTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final monitoringsAsync = ref.watch(myMonitoringsProvider);

    return monitoringsAsync.when(
      loading: () => const ApasbacLoading(),
      error: (err, _) => _ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(myMonitoringsProvider),
      ),
      data: (monitorings) {
        if (monitorings.isEmpty) {
          return const _EmptyView(message: 'Nenhum monitoramento encontrado');
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(myMonitoringsProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: monitorings.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _MonitoringReviewCard(
              monitoring: monitorings[i],
            ),
          ),
        );
      },
    );
  }
}

class _MonitoringReviewCard extends ConsumerStatefulWidget {
  final MonitoringModel monitoring;
  const _MonitoringReviewCard({required this.monitoring});

  @override
  ConsumerState<_MonitoringReviewCard> createState() =>
      _MonitoringReviewCardState();
}

class _MonitoringReviewCardState extends ConsumerState<_MonitoringReviewCard> {
  bool _reviewing = false;
  MonitoringModel get monitoring => widget.monitoring;
  @override
  Widget build(BuildContext context) {
    final statusColor = switch (monitoring.status) {
      'PENDING' => SemanticColors.pending,
      'IN_REVIEW' => SemanticColors.review,
      'APPROVED' => SemanticColors.approved,
      'REJECTED' => SemanticColors.rejected,
      _ => AppColors.muted,
    };

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    monitoring.animal?.name ?? 'Animal #${monitoring.animalId}',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Chip(
                  label: Text(monitoring.statusLabel),
                  side: BorderSide(color: statusColor.withOpacity(0.35)),
                  backgroundColor: statusColor.withOpacity(0.1),
                  labelStyle: TextStyle(
                    color: statusColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Tutor: ${monitoring.tutorId}',
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      context.push('/home/monitoring/${monitoring.id}'),
                  icon: const Icon(Icons.visibility_outlined),
                  label: const Text('Ver mídias'),
                ),
                if (monitoring.isUnderReview) ...[
                  OutlinedButton.icon(
                    label: const Text('Rejeitar'),
                    onPressed:
                        _reviewing ? null : () => _review(context, ref, false),
                    icon: const Icon(Icons.close_rounded),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    label: const Text('Aprovar'),
                    onPressed:
                        _reviewing ? null : () => _review(context, ref, true),
                    icon: const Icon(Icons.check_rounded),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _review(
      BuildContext context, WidgetRef ref, bool approved) async {
    if (_reviewing) return;
    setState(() => _reviewing = true);
    final notes = await _askNotes(context, approved);
    if (!mounted) return;
    if (notes == null) {
      setState(() => _reviewing = false);
      return;
    }

    try {
      await ref.read(monitoringServiceProvider).reviewMonitoring(
            monitoringId: monitoring.id,
            approved: approved,
            notes: notes,
          );
      ref.invalidate(myMonitoringsProvider);
      ref.invalidate(monitoringDetailProvider(monitoring.id));
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(approved
                ? 'Monitoramento aprovado.'
                : 'Monitoramento rejeitado.'),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao revisar: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }
}

class _AdoptionsTab extends ConsumerWidget {
  const _AdoptionsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final animalsAsync = ref.watch(adminAnimalsProvider);
    final usersAsync = ref.watch(adminUsersProvider);

    return animalsAsync.when(
      loading: () => const ApasbacLoading(),
      error: (err, _) => _ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(adminAnimalsProvider),
      ),
      data: (animals) {
        final availableAnimals = animals.where((a) => !a.isAdopted).toList();
        if (availableAnimals.isEmpty) {
          return const _EmptyView(
              message: 'Nenhum animal disponível para adoção');
        }

        return usersAsync.when(
          loading: () => const ApasbacLoading(),
          error: (err, _) => _ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(adminUsersProvider),
          ),
          data: (users) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(adminAnimalsProvider);
              ref.invalidate(adminUsersProvider);
            },
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: availableAnimals.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (_, i) => _AdoptionCard(
                animal: availableAnimals[i],
                users: users,
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AdoptionCard extends ConsumerWidget {
  final AnimalModel animal;
  final List<UserModel> users;

  const _AdoptionCard({
    required this.animal,
    required this.users,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child:
              Text(animal.name.isNotEmpty ? animal.name[0].toUpperCase() : '?'),
        ),
        title: Text(animal.name),
        subtitle: Text('${animal.breed} • ${animal.sizeLabel}'),
        trailing: FilledButton(
          onPressed: () => _linkAdopter(context, ref),
          child: const Text('Adotar'),
        ),
      ),
    );
  }

  Future<void> _linkAdopter(BuildContext context, WidgetRef ref) async {
    final adopter = await showModalBottomSheet<UserModel>(
      context: context,
      showDragHandle: true,
      builder: (_) => _UserPicker(users: users),
    );
    if (adopter == null) return;

    try {
      await ref.read(animalServiceProvider).linkAdopter(
            animalId: animal.id,
            userId: adopter.id,
          );
      ref.invalidate(adminAnimalsProvider);
      ref.invalidate(myAnimalsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('${animal.name} vinculado a ${adopter.fullName}.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Erro ao vincular adoção: $e')),
        );
      }
    }
  }
}

class _UsersTab extends ConsumerWidget {
  const _UsersTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usersAsync = ref.watch(adminUsersProvider);

    return usersAsync.when(
      loading: () => const ApasbacLoading(),
      error: (err, _) => _ErrorView(
        message: err.toString(),
        onRetry: () => ref.invalidate(adminUsersProvider),
      ),
      data: (users) {
        if (users.isEmpty) {
          return const _EmptyView(message: 'Nenhum usuário encontrado');
        }

        return RefreshIndicator(
          onRefresh: () async => ref.invalidate(adminUsersProvider),
          child: ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: users.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (_, i) => _UserRoleTile(user: users[i]),
          ),
        );
      },
    );
  }
}

class _UserRoleTile extends ConsumerWidget {
  final UserModel user;
  const _UserRoleTile({required this.user});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const roles = ['ADMIN', 'STAFF', 'TUTOR', 'USER'];

    return Card(
      child: ListTile(
        leading: CircleAvatar(
          child: Text(
              user.fullName.isNotEmpty ? user.fullName[0].toUpperCase() : '?'),
        ),
        title: Text(user.fullName),
        subtitle: Text(user.email),
        trailing: ref.watch(authProvider).valueOrNull?.role != 'ADMIN'
            ? RoleBadge(role: user.role)
            : DropdownButton<String>(
                value: roles.contains(user.role) ? user.role : 'USER',
                items: roles
                    .map((role) => DropdownMenuItem(
                        value: role, child: RoleBadge(role: role)))
                    .toList(),
                onChanged: (role) async {
                  if (role == null || role == user.role) return;
                  try {
                    await ref
                        .read(userServiceProvider)
                        .updateRole(user.id, role);
                    ref.invalidate(adminUsersProvider);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                            content:
                                Text('Cargo de ${user.fullName} atualizado.')),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('Erro ao mudar cargo: $e')),
                      );
                    }
                  }
                },
              ),
      ),
    );
  }
}

class _UserPicker extends StatelessWidget {
  final List<UserModel> users;
  const _UserPicker({required this.users});

  @override
  Widget build(BuildContext context) {
    final eligible = users
        .where((user) => user.role == 'USER' || user.role == 'TUTOR')
        .toList();

    if (eligible.isEmpty) {
      return const SizedBox(
        height: 180,
        child: Center(child: Text('Nenhum usuário elegível encontrado')),
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: eligible.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final user = eligible[i];
        return ListTile(
          leading: CircleAvatar(
            child: Text(user.fullName.isNotEmpty
                ? user.fullName[0].toUpperCase()
                : '?'),
          ),
          title: Text(user.fullName),
          subtitle:
              Text('${user.email} • ${SemanticColors.roleLabel(user.role)}'),
          onTap: () => Navigator.of(context).pop(user),
        );
      },
    );
  }
}

Future<String?> _askNotes(BuildContext context, bool approved) async {
  final controller = TextEditingController();
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title:
          Text(approved ? 'Aprovar monitoramento' : 'Rejeitar monitoramento'),
      content: TextField(
        controller: controller,
        decoration: const InputDecoration(
          labelText: 'Observações',
          border: OutlineInputBorder(),
        ),
        minLines: 2,
        maxLines: 4,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(controller.text),
          child: Text(approved ? 'Aprovar' : 'Rejeitar'),
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorView({
    required this.message,
    required this.onRetry,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.error_outline, size: 48, color: AppColors.red),
            const SizedBox(height: 12),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            ElevatedButton(
              onPressed: onRetry,
              child: const Text('Tentar novamente'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyView extends StatelessWidget {
  final String message;
  const _EmptyView({required this.message});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        message,
        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
      ),
    );
  }
}
