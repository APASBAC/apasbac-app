import '../../../../core/widgets/apasbac_loading.dart';
import '../../../../core/theme/semantic_colors.dart';
import '../../../../core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../../../../core/widgets/search_field.dart';
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
      length: 5,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Administração'),
          bottom: const TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(icon: Icon(Icons.fact_check_outlined), text: 'Validações'),
              Tab(icon: Icon(Icons.pets_outlined), text: 'Animais'),
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
                child: _AnimalsTab()),
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

class _MonitoringReviewTab extends ConsumerStatefulWidget {
  const _MonitoringReviewTab();

  @override
  ConsumerState<_MonitoringReviewTab> createState() =>
      _MonitoringReviewTabState();
}

class _MonitoringReviewTabState extends ConsumerState<_MonitoringReviewTab> {
  String _query = '';
  String? _status;

  static const _statuses = {
    'IN_REVIEW': 'Em análise',
    'PENDING': 'Aguardando',
    'APPROVED': 'Aprovados',
    'REJECTED': 'Rejeitados',
  };

  @override
  Widget build(BuildContext context) {
    final monitoringsAsync = ref.watch(myMonitoringsProvider);

    return Column(
      children: [
        SearchField(
          hint: 'Buscar por tutor, e-mail ou animal',
          onChanged: (v) => setState(() => _query = v),
        ),
        _FilterChips(
          options: _statuses,
          selected: _status,
          onSelected: (v) => setState(() => _status = v),
        ),
        Expanded(
          child: monitoringsAsync.when(
            loading: () => const ApasbacLoading(),
            error: (err, _) => _ErrorView(
              message: err.toString(),
              onRetry: () => ref.invalidate(myMonitoringsProvider),
            ),
            data: (all) {
              final monitorings = all
                  .where((m) => _status == null || m.status == _status)
                  .where((m) => matchesSearch(_query, [
                        m.tutorName,
                        m.tutorEmail,
                        m.animal?.name,
                        m.animal?.breed,
                        m.animal?.species,
                        m.animal?.adopterName,
                      ]))
                  .toList();
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(myMonitoringsProvider),
                child: monitorings.isEmpty
                    ? _EmptyView(
                        message: all.isEmpty
                            ? 'Nenhum monitoramento encontrado'
                            : 'Nenhum monitoramento corresponde à busca')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: monitorings.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) => _MonitoringReviewCard(
                          key: ValueKey(monitorings[i].id),
                          monitoring: monitorings[i],
                        ),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _MonitoringReviewCard extends ConsumerStatefulWidget {
  final MonitoringModel monitoring;
  const _MonitoringReviewCard({super.key, required this.monitoring});

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
              'Tutor: ${monitoring.tutorName ?? monitoring.animal?.adopterName ?? monitoring.tutorId}'
              '${monitoring.tutorEmail != null ? ' • ${monitoring.tutorEmail}' : ''}',
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

/// Todos os animais cadastrados, com busca e filtro por situação.
class _AnimalsTab extends ConsumerStatefulWidget {
  const _AnimalsTab();

  @override
  ConsumerState<_AnimalsTab> createState() => _AnimalsTabState();
}

class _AnimalsTabState extends ConsumerState<_AnimalsTab> {
  String _query = '';
  String? _filter;

  @override
  Widget build(BuildContext context) {
    final animalsAsync = ref.watch(adminAnimalsProvider);
    return Column(
      children: [
        SearchField(
          hint: 'Buscar animal, raça ou tutor',
          onChanged: (v) => setState(() => _query = v),
        ),
        _FilterChips(
          options: const {'AVAILABLE': 'Disponíveis', 'ADOPTED': 'Adotados'},
          selected: _filter,
          onSelected: (v) => setState(() => _filter = v),
        ),
        Expanded(
          child: animalsAsync.when(
            loading: () => const ApasbacLoading(),
            error: (err, _) => _ErrorView(
              message: err.toString(),
              onRetry: () => ref.invalidate(adminAnimalsProvider),
            ),
            data: (all) {
              final animals = all
                  .where((a) =>
                      _filter == null ||
                      (_filter == 'ADOPTED' ? a.isAdopted : !a.isAdopted))
                  .where((a) => matchesSearch(_query, [
                        a.name,
                        a.breed,
                        a.species,
                        a.adopterName,
                        a.sexLabel,
                        a.sizeLabel,
                        '#${a.id}',
                      ]))
                  .toList();
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminAnimalsProvider),
                child: animals.isEmpty
                    ? _EmptyView(
                        message: all.isEmpty
                            ? 'Nenhum animal cadastrado'
                            : 'Nenhum animal corresponde à busca')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: animals.length + 1,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) => i == 0
                            ? Text(
                                '${animals.length} de ${all.length} animais',
                                style: TextStyle(
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              )
                            : _AnimalTile(animal: animals[i - 1]),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _AnimalTile extends StatelessWidget {
  final AnimalModel animal;
  const _AnimalTile({required this.animal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        leading: _AnimalAvatar(animal: animal),
        title: Text(animal.name,
            style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text([
          animal.summary,
          if (animal.isAdopted)
            'Tutor: ${animal.adopterName ?? 'não informado'}'
          else
            'Disponível para adoção',
        ].join('\n')),
        isThreeLine: true,
        trailing: Icon(
          animal.isAdopted
              ? Icons.home_rounded
              : Icons.volunteer_activism_outlined,
          color: animal.isAdopted ? cs.primary : cs.onSurfaceVariant,
        ),
        onTap: () => context.push('/home/animals/${animal.id}'),
      ),
    );
  }
}

class _AnimalAvatar extends StatelessWidget {
  final AnimalModel animal;
  const _AnimalAvatar({required this.animal});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final photo = animal.primaryPhoto;
    final fallback = CircleAvatar(
      radius: 24,
      backgroundColor: cs.primaryContainer,
      child: Text(
        animal.name.isNotEmpty ? animal.name[0].toUpperCase() : '?',
        style: TextStyle(color: cs.onPrimaryContainer),
      ),
    );
    if (photo == null) return fallback;
    return ClipOval(
      child: CachedNetworkImage(
        imageUrl: photo.url,
        width: 48,
        height: 48,
        fit: BoxFit.cover,
        memCacheWidth: 144,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      ),
    );
  }
}

class _FilterChips extends StatelessWidget {
  final Map<String, String> options;
  final String? selected;
  final ValueChanged<String?> onSelected;
  const _FilterChips(
      {required this.options,
      required this.selected,
      required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          ChoiceChip(
            label: const Text('Todos'),
            selected: selected == null,
            onSelected: (_) => onSelected(null),
          ),
          for (final e in options.entries) ...[
            const SizedBox(width: 8),
            ChoiceChip(
              label: Text(e.value),
              selected: selected == e.key,
              onSelected: (_) => onSelected(selected == e.key ? null : e.key),
            ),
          ],
        ],
      ),
    );
  }
}

class _AdoptionsTab extends ConsumerStatefulWidget {
  const _AdoptionsTab();

  @override
  ConsumerState<_AdoptionsTab> createState() => _AdoptionsTabState();
}

class _AdoptionsTabState extends ConsumerState<_AdoptionsTab> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
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
        final shown = availableAnimals
            .where((a) => matchesSearch(
                _query, [a.name, a.breed, a.species, '#${a.id}']))
            .toList();

        return usersAsync.when(
          loading: () => const ApasbacLoading(),
          error: (err, _) => _ErrorView(
            message: err.toString(),
            onRetry: () => ref.invalidate(adminUsersProvider),
          ),
          data: (users) => Column(
            children: [
              SearchField(
                hint: 'Buscar animal disponível',
                onChanged: (v) => setState(() => _query = v),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async {
                    ref.invalidate(adminAnimalsProvider);
                    ref.invalidate(adminUsersProvider);
                  },
                  child: shown.isEmpty
                      ? const _EmptyView(
                          message: 'Nenhum animal corresponde à busca')
                      : ListView.separated(
                          padding: const EdgeInsets.all(16),
                          itemCount: shown.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(height: 12),
                          itemBuilder: (_, i) => _AdoptionCard(
                            animal: shown[i],
                            users: users,
                          ),
                        ),
                ),
              ),
            ],
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
        leading: _AnimalAvatar(animal: animal),
        title: Text(animal.name),
        subtitle: Text([
          animal.breedLabel,
          if (animal.hasSex) animal.sexLabel,
          if (animal.sizeLabel.isNotEmpty) animal.sizeLabel,
        ].join(' • ')),
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
      isScrollControlled: true,
      builder: (_) => _UserPicker(users: users, animalName: animal.name),
    );
    if (adopter == null || !context.mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Confirmar adoção'),
        content: Text('Vincular ${animal.name} a ${adopter.fullName}?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(animalServiceProvider).linkAdopter(
            animalId: animal.id,
            userId: adopter.id,
          );
      ref.invalidate(adminAnimalsProvider);
      ref.invalidate(adminUsersProvider);
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

class _UsersTab extends ConsumerStatefulWidget {
  const _UsersTab();

  @override
  ConsumerState<_UsersTab> createState() => _UsersTabState();
}

class _UsersTabState extends ConsumerState<_UsersTab> {
  String _query = '';
  String? _role;

  @override
  Widget build(BuildContext context) {
    final usersAsync = ref.watch(adminUsersProvider);

    return Column(
      children: [
        SearchField(
          hint: 'Buscar por nome, e-mail, telefone ou CPF',
          onChanged: (v) => setState(() => _query = v),
        ),
        _FilterChips(
          options: {
            for (final r in const ['ADMIN', 'STAFF', 'TUTOR', 'USER'])
              r: SemanticColors.roleLabel(r),
          },
          selected: _role,
          onSelected: (v) => setState(() => _role = v),
        ),
        Expanded(
          child: usersAsync.when(
            loading: () => const ApasbacLoading(),
            error: (err, _) => _ErrorView(
              message: err.toString(),
              onRetry: () => ref.invalidate(adminUsersProvider),
            ),
            data: (all) {
              final users = all
                  .where((u) => _role == null || u.role == _role)
                  .where((u) => _userMatches(u, _query))
                  .toList();
              return RefreshIndicator(
                onRefresh: () async => ref.invalidate(adminUsersProvider),
                child: users.isEmpty
                    ? _EmptyView(
                        message: all.isEmpty
                            ? 'Nenhum usuário encontrado'
                            : 'Nenhum usuário corresponde à busca')
                    : ListView.separated(
                        padding: const EdgeInsets.all(16),
                        itemCount: users.length,
                        separatorBuilder: (_, __) =>
                            const SizedBox(height: 12),
                        itemBuilder: (_, i) => _UserRoleTile(
                            key: ValueKey(users[i].id), user: users[i]),
                      ),
              );
            },
          ),
        ),
      ],
    );
  }
}

bool _userMatches(UserModel u, String query) => matchesSearch(query, [
      u.fullName,
      u.email,
      u.phone,
      u.cpf,
      SemanticColors.roleLabel(u.role),
    ]);

class _UserRoleTile extends ConsumerWidget {
  final UserModel user;
  const _UserRoleTile({super.key, required this.user});

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
        subtitle: Text(
            [user.email, if (user.phone.isNotEmpty) user.phone].join('\n')),
        isThreeLine: user.phone.isNotEmpty,
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

class _UserPicker extends StatefulWidget {
  final List<UserModel> users;
  final String animalName;
  const _UserPicker({required this.users, required this.animalName});

  @override
  State<_UserPicker> createState() => _UserPickerState();
}

class _UserPickerState extends State<_UserPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    final eligible = widget.users
        .where((user) => user.role == 'USER' || user.role == 'TUTOR')
        .where((user) => _userMatches(user, _query))
        .toList();

    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) => Padding(
        padding: EdgeInsets.only(
            bottom: MediaQuery.of(context).viewInsets.bottom),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Text('Adotante de ${widget.animalName}',
                  style: Theme.of(context).textTheme.titleMedium),
            ),
            SearchField(
              hint: 'Buscar por nome, e-mail, telefone ou CPF',
              onChanged: (v) => setState(() => _query = v),
            ),
            Expanded(
              child: eligible.isEmpty
                  ? Center(
                      child: Text(_query.isEmpty
                          ? 'Nenhum usuário elegível encontrado'
                          : 'Nenhum usuário corresponde à busca'))
                  : ListView.separated(
                      controller: scrollController,
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
                          subtitle: Text(
                              '${user.email} • ${SemanticColors.roleLabel(user.role)}'),
                          onTap: () => Navigator.of(context).pop(user),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
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
