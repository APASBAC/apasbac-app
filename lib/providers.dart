import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/models/user_model.dart';
import '../core/models/animal_model.dart';
import '../core/models/monitoring_model.dart';
import '../core/services/auth_service.dart';
import '../core/services/animal_service.dart';
import '../core/services/monitoring_service.dart';
import '../core/services/user_service.dart';

// ─── Services ───────────────────────────────────────────────
final authServiceProvider = Provider<AuthService>((_) => AuthService());
final animalServiceProvider = Provider<AnimalService>((_) => AnimalService());
final monitoringServiceProvider =
    Provider<MonitoringService>((_) => MonitoringService());
final userServiceProvider = Provider<UserService>((_) => UserService());

// ─── Auth State ─────────────────────────────────────────────
class AuthNotifier extends AsyncNotifier<UserModel?> {
  @override
  Future<UserModel?> build() async {
    final svc = ref.read(authServiceProvider);
    final loggedIn = await svc.isLoggedIn();
    if (!loggedIn) return null;
    try {
      return await svc.getMe();
    } catch (_) {
      return null;
    }
  }

  Future<String?> login(String email, String password) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
      () => ref.read(authServiceProvider).login(email, password),
    );
    state = result;
    if (result.hasError) {
      state = const AsyncData(null);
      return result.error?.toString() ?? 'Erro ao fazer login';
    }
    return null;
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
    final svc = ref.read(authServiceProvider);
    try {
      await svc.register(
        fullName: fullName,
        email: email,
        phone: phone,
        cpf: cpf,
        password: password,
        confirmPassword: confirmPassword,
      );
    } catch (e) {
      state = const AsyncData(null);
      return e.toString();
    }
    final result = await AsyncValue.guard(() => svc.login(email, password));
    state = result;
    if (result.hasError) {
      state = const AsyncData(null);
      return result.error?.toString() ?? 'Erro ao fazer login após cadastro';
    }
    return null;
  }

  Future<void> logout() async {
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
        role: user.role));
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
  return ref.read(animalServiceProvider).getAnimals();
});

final adminUsersProvider = FutureProvider<List<UserModel>>((ref) async {
  final user = ref.watch(authProvider).valueOrNull;
  if (user == null || !user.isAdminOrStaff) return [];
  return ref.read(userServiceProvider).getUsers();
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
    return svc.getMyMonitorings();
  } else if (user.isAdminOrStaff) {
    return svc.getAllMonitorings();
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
