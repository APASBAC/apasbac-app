import 'package:dio/dio.dart';
import '../core/utils/friendly_error.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/user_model.dart';
import '../core/models/animal_model.dart';
import '../core/models/monitoring_model.dart';
import '../core/services/auth_service.dart';
import '../core/services/animal_service.dart';
import '../core/services/monitoring_service.dart';
import '../core/services/user_service.dart';
import '../core/services/monitoring_upload_queue.dart';

// ─── Services ───────────────────────────────────────────────
final authServiceProvider = Provider<AuthService>((_) => AuthService());
final animalServiceProvider = Provider<AnimalService>((_) => AnimalService());
final monitoringServiceProvider =
    Provider<MonitoringService>((_) => MonitoringService());
final userServiceProvider = Provider<UserService>((_) => UserService());

/// Fila de envio dos monitoramentos em segundo plano.
final uploadQueueProvider = ChangeNotifierProvider<MonitoringUploadQueue>(
    (_) => MonitoringUploadQueue.instance);

// ─── Auth State ─────────────────────────────────────────────

/// Aviso exibido na tela de login (ex.: sessão expirada).
final authNoticeProvider = StateProvider<String?>((_) => null);

String _apiMessage(Object e, String fallback) {
  final f = describeError(e);
  return f.kind == ErrorKind.unknown ? fallback : f.text;
}

class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final svc = ref.read(authServiceProvider);
    // Sessão recusada pela API durante o uso: volta para o login.
    final expired = svc.client.sessionExpired;
    void onExpired() {
      if (state.valueOrNull == null) return;
      ref.read(authNoticeProvider.notifier).state =
          'Sua sessão expirou. Entre novamente.';
      state = const AsyncData(null);
    }

    expired.addListener(onExpired);
    ref.onDispose(() => expired.removeListener(onExpired));
    try {
      return await svc.restoreSession();
    } catch (_) {
      return null;
    }
  }

  Future<String?> login(String email, String password,
      {bool remember = true}) async {
    state = const AsyncLoading();
    try {
      final user = await ref
          .read(authServiceProvider)
          .login(email, password, remember: remember);
      ref.read(authNoticeProvider.notifier).state = null;
      state = AsyncData(user);
      return null;
    } catch (e) {
      state = const AsyncData(null);
      // No login, 401 significa e-mail ou senha errados (não sessão expirada).
      if (e is DioException && e.response?.statusCode == 401) {
        return 'E-mail ou senha incorretos.';
      }
      return _apiMessage(e, 'Não foi possível entrar. Tente de novo.');
    }
  }

  Future<String?> register({
    required String fullName,
    required String email,
    required String phone,
    required String cpf,
    required String password,
    required String confirmPassword,
  }) async {
    state = const AsyncLoading();
    try {
      final user = await ref.read(authServiceProvider).register(
            fullName: fullName,
            email: email,
            phone: phone,
            cpf: cpf,
            password: password,
            confirmPassword: confirmPassword,
          );
      state = AsyncData(user);
      return null;
    } catch (e) {
      state = const AsyncData(null);
      return _apiMessage(e, 'Não foi possível concluir o cadastro.');
    }
  }

  Future<void> logout() async {
    // Envios pendentes pertencem a quem está saindo da conta.
    await ref.read(uploadQueueProvider).clearAll();
    await ref.read(authServiceProvider).logout();
    state = const AsyncData(null);
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(
      () => ref.read(authServiceProvider).getMe(),
    );
  }

  void updateLocalProfile({required String fullName, required String phone}) {
    final user = state.valueOrNull;
    if (user == null) return;
    state = AsyncData(UserModel(
        id: user.id,
        fullName: fullName,
        email: user.email,
        phone: phone,
        role: user.role,
        cpf: user.cpf));
  }
}

final authProvider =
    AsyncNotifierProvider<AuthNotifier, UserModel?>(AuthNotifier.new);

// ─── Animals ─────────────────────────────────────────────────
final myAnimalsProvider = FutureProvider<List<AnimalModel>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return [];
  return ref.read(animalServiceProvider).getMyAnimals(user.id);
});

final animalDetailProvider =
    FutureProvider.family<AnimalModel, int>((ref, id) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user != null && user.isAdminOrStaff) {
    return ref.read(animalServiceProvider).getAnimalAdmin(id);
  }
  return ref.read(animalServiceProvider).getAnimalById(id);
});

final adminAnimalsProvider = FutureProvider<List<AnimalModel>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null || !user.isAdminOrStaff) return [];
  return ref.read(animalServiceProvider).getAllAnimals();
});

final adminUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null || !user.isAdminOrStaff) return [];
  return ref.read(userServiceProvider).getAllUsers();
});

// ─── Monitoring ───────────────────────────────────────────────
final myMonitoringsProvider =
    FutureProvider<List<MonitoringModel>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null) return [];

  final svc = ref.read(monitoringServiceProvider);

  // TUTOR → /monitoring/mine (próprios monitoramentos)
  // ADMIN/STAFF → /monitoring (lista geral)
  if (user.isTutor) {
    return svc.getAllMyMonitorings();
  } else if (user.isAdminOrStaff) {
    return svc.getEveryMonitoring();
  }

  return [];
});

final monitoringDetailProvider =
    FutureProvider.family<MonitoringModel, String>((ref, id) async {
  final user = ref.watch(authProvider).valueOrNull;
  return ref.read(monitoringServiceProvider).getMonitoringById(
        id,
        isAdminOrStaff: user?.isAdminOrStaff ?? false,
      );
});
