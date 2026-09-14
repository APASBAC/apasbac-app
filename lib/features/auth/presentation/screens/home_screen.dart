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
        title: const ApasbacLogo(),
        actions: [
          PopupMenuButton(
            icon: CircleAvatar(
              backgroundColor: cs.primaryContainer,
              radius: 18,
              child: Text(
                user?.fullName.substring(0, 1).toUpperCase() ?? '?',
                style: TextStyle(
                    color: cs.onPrimaryContainer, fontWeight: FontWeight.bold),
              ),
            ),
            itemBuilder: (_) => <PopupMenuEntry<dynamic>>[
              PopupMenuItem(
                enabled: false,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(user?.fullName ?? '',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    Text(user?.email ?? '',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                    Text('Perfil: ${user?.role ?? ''}',
                        style:
                            const TextStyle(fontSize: 12, color: Colors.grey)),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                onTap: () async {
                  await ref.read(authProvider.notifier).logout();
                },
                child: const Row(children: [
                  Icon(Icons.logout, size: 20),
                  SizedBox(width: 8),
                  Text('Sair'),
                ]),
              ),
            ],
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Olá, ${user?.fullName.split(' ').first ?? 'Tutor'} 👋',
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

              // Cards de navegação
              _NavCard(
                icon: Icons.favorite_rounded,
                color: const Color(0xFF2E7D32),
                title: 'Meus Animais',
                subtitle: 'Veja seus pets adotados',
                onTap: () => context.go('/home/animals'),
              ),
              const SizedBox(height: 16),
              _NavCard(
                icon: Icons.monitor_heart_rounded,
                color: const Color(0xFF1565C0),
                title: 'Monitoramentos',
                subtitle: 'Acompanhe e envie relatórios',
                onTap: () => context.go('/home/monitoring'),
              ),
              if (user?.isAdminOrStaff == true) ...[
                const SizedBox(height: 16),
                _NavCard(
                  icon: Icons.admin_panel_settings_rounded,
                  color: const Color(0xFF6A1B9A),
                  title: 'Administração',
                  subtitle: 'Gerencie adoções, usuários e validações',
                  onTap: () => context.go('/home/admin'),
                ),
              ],
            ],
          ),
        ),
      ),
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
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: color,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.white, size: 28),
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
                      style:
                          TextStyle(color: Colors.grey.shade600, fontSize: 13)),
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
