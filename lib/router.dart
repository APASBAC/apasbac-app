import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'providers.dart';
import 'features/auth/presentation/screens/login_screen.dart';
import 'features/auth/presentation/screens/register_screen.dart';
import 'features/auth/presentation/screens/forgot_password_screen.dart';
import 'features/animals/presentation/screens/my_animals_screen.dart';
import 'features/animals/presentation/screens/animal_detail_screen.dart';
import 'features/monitoring/presentation/screens/monitoring_list_screen.dart';
import 'features/monitoring/presentation/screens/monitoring_detail_screen.dart';
import 'features/monitoring/presentation/screens/monitoring_submit_screen.dart';
import 'features/auth/presentation/screens/home_screen.dart';
import 'features/admin/presentation/screens/admin_screen.dart';
import 'features/admin/presentation/screens/admin_forms.dart';

// Tela de splash/loading global
class _SplashScreen extends StatelessWidget {
  const _SplashScreen();

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      body: Center(child: CircularProgressIndicator()),
    );
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final authState = ref.watch(authProvider);

  return GoRouter(
    initialLocation: '/splash',
    redirect: (context, state) {
      final isLoading = authState.isLoading;
      final isLoggedIn = authState.valueOrNull != null;
      final isSplash = state.matchedLocation == '/splash';
      final isAuthRoute = state.matchedLocation.startsWith('/auth');

      // Enquanto carrega, manda para splash
      if (isLoading) {
        return isSplash ? null : '/splash';
      }

      // Carregou: sai do splash para o destino certo
      if (isSplash) {
        return isLoggedIn ? '/home' : '/auth/login';
      }

      // Proteção de rotas
      if (!isLoggedIn && !isAuthRoute) return '/auth/login';
      if (isLoggedIn && isAuthRoute) return '/home';
      if (state.matchedLocation.startsWith('/home/admin') &&
          !(authState.valueOrNull?.isAdminOrStaff ?? false)) {
        return '/home';
      }

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const _SplashScreen()),
      GoRoute(path: '/auth/login', builder: (_, __) => const LoginScreen()),
      GoRoute(
          path: '/auth/register', builder: (_, __) => const RegisterScreen()),
      GoRoute(
          path: '/auth/forgot-password',
          builder: (_, __) => const ForgotPasswordScreen()),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
        routes: [
          GoRoute(
            path: 'animals',
            builder: (_, __) => const MyAnimalsScreen(),
            routes: [
              GoRoute(
                path: ':id',
                builder: (_, state) => AnimalDetailScreen(
                    id: int.parse(state.pathParameters['id']!)),
              ),
            ],
          ),
          GoRoute(
            path: 'monitoring',
            builder: (_, __) => const MonitoringListScreen(),
            routes: [
              GoRoute(
                path: ':id/submit',
                builder: (_, state) => MonitoringSubmitScreen(
                    monitoringId: state.pathParameters['id']!),
              ),
              GoRoute(
                path: ':id',
                builder: (_, state) =>
                    MonitoringDetailScreen(id: state.pathParameters['id']!),
              ),
            ],
          ),
          GoRoute(
            path: 'admin',
            builder: (_, __) => const AdminScreen(),
            routes: [
              GoRoute(
                  path: 'animal/new',
                  builder: (_, __) => const AnimalCreateScreen()),
              GoRoute(
                  path: 'monitoring/new',
                  builder: (_, __) => const MonitoringCreateScreen()),
            ],
          ),
        ],
      ),
    ],
  );
});
