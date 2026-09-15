import '../../../../core/theme/semantic_colors.dart';
import '../../../../core/widgets/app_content.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/widgets/apasbac_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../../../providers.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authProvider).valueOrNull;
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 88,
        title: const ApasbacLogo(height: 64),
        actions: [
          IconButton(
            tooltip: 'Meu perfil',
            onPressed: () => context.push('/home/profile'),
            icon: CircleAvatar(
              backgroundColor: SemanticColors.role(user?.role ?? 'USER')
                  .withValues(alpha: .12),
              child: Text(
                  (user?.fullName.isNotEmpty ?? false)
                      ? user!.fullName[0].toUpperCase()
                      : '?',
                  style: TextStyle(
                      color: SemanticColors.role(user?.role ?? 'USER'),
                      fontWeight: FontWeight.w700)),
            ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: AppContent(
          maxWidth: 760,
          child: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Olá, ${user?.fullName.split(' ').first ?? 'Tutor'}',
                    style: Theme.of(context)
                        .textTheme
                        .headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'O que você quer ver hoje?',
                    style: TextStyle(color: cs.onSurfaceVariant),
                  ),
                  const SizedBox(height: 32),
                  if (user?.isAdminOrStaff == true) ...[
                    Row(children: [
                      RoleBadge(role: user!.role),
                      const SizedBox(width: 12),
                      const Expanded(child: Text('Equipe APASBAC'))
                    ]),
                    const SizedBox(height: 16),
                    Card(
                        child: Padding(
                            padding: const EdgeInsets.all(22),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Icon(Icons.volunteer_activism_outlined,
                                    size: 28),
                                const SizedBox(height: 14),
                                Text('Cada cuidado faz a diferença.',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleLarge
                                        ?.copyWith(
                                            fontWeight: FontWeight.w700)),
                                const SizedBox(height: 8),
                                const Text(
                                    'Organize adoções e acompanhe os relatórios dos tutores em um só lugar.',
                                    style: TextStyle(height: 1.5)),
                                const SizedBox(height: 18),
                                FilledButton.icon(
                                    onPressed: () => context.go('/home/admin'),
                                    icon: const Icon(Icons.arrow_forward),
                                    label: const Text('Abrir administração')),
                              ],
                            ))),
                  ] else
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(24),
                      decoration: BoxDecoration(
                          color: AppColors.soft,
                          borderRadius: BorderRadius.circular(24)),
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.favorite_outline_rounded,
                                size: 30),
                            const SizedBox(height: 16),
                            Text('Uma nova vida.\nUm cuidado para sempre.',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineSmall
                                    ?.copyWith(
                                        fontWeight: FontWeight.w700,
                                        height: 1.2)),
                            const SizedBox(height: 12),
                            const Text(
                                'A APASBAC continua por perto em cada etapa dessa história.',
                                style: TextStyle(height: 1.5)),
                          ]),
                    ),
                  const SizedBox(height: 28),
                  Text('Seu dia a dia',
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  _NavCard(
                    icon: Icons.favorite_rounded,
                    color: AppColors.red,
                    title: 'Meus Animais',
                    subtitle: 'Veja seus pets adotados',
                    onTap: () => context.go('/home/animals'),
                  ),
                  const SizedBox(height: 16),
                  _NavCard(
                    icon: Icons.monitor_heart_rounded,
                    color: AppColors.red,
                    title: 'Monitoramentos',
                    subtitle: user?.isAdminOrStaff == true
                        ? 'Acompanhe os relatórios dos tutores'
                        : 'Acompanhe e envie relatórios',
                    onTap: () => context.go('/home/monitoring'),
                  ),
                  if (user?.isAdminOrStaff == true) ...[
                    const SizedBox(height: 16),
                    _NavCard(
                      icon: Icons.admin_panel_settings_rounded,
                      color: AppColors.red,
                      title: 'Administração',
                      subtitle: 'Gerencie adoções, usuários e validações',
                      onTap: () => context.go('/home/admin'),
                    ),
                  ],
                ],
              ),
            ),
          )),
    );
  }
}

class _NavCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _NavCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: AppColors.cream,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: AppColors.border),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.soft,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: AppColors.red, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 17, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: TextStyle(color: AppColors.muted, fontSize: 13)),
                ],
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: color),
          ],
        ),
      ),
    );
  }
}
