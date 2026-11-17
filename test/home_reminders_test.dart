import 'package:apasbac_app/core/models/animal_model.dart';
import 'package:apasbac_app/core/models/monitoring_model.dart';
import 'package:apasbac_app/core/models/user_model.dart';
import 'package:apasbac_app/core/notifications/monitoring_reminders.dart';
import 'package:apasbac_app/core/theme/app_theme.dart';
import 'package:apasbac_app/features/auth/presentation/screens/home_screen.dart';
import 'package:apasbac_app/providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _User extends AuthNotifier {
  @override
  Future<UserModel?> build() async => const UserModel(
      id: 'u1', fullName: 'Ana Lima', email: 'a@x', phone: '', role: 'TUTOR');
}

MonitoringModel _m(String id, String status, DateTime? due) =>
    MonitoringModel.fromJson({
      'id': id,
      'animalId': 1,
      'status': status,
      if (due != null) 'dueDate': due.toUtc().toIso8601String(),
      'animal': {'id': 1, 'name': 'Bolt'},
    });

Widget _home(List<AnimalModel> animals, List<MonitoringModel> monitorings) =>
    ProviderScope(overrides: [
      authProvider.overrideWith(_User.new),
      myAnimalsProvider.overrideWith((ref) async => animals),
      myMonitoringsProvider.overrideWith((ref) async => monitorings),
    ], child: MaterialApp(theme: buildAppTheme(), home: const HomeScreen()));

void main() {
  testWidgets('Sem animais nem monitoramentos os cards não aparecem',
      (tester) async {
    await tester.pumpWidget(_home([], []));
    await tester.pumpAndSettle();
    expect(find.text('Meus Animais'), findsNothing);
    expect(find.text('Monitoramentos'), findsNothing);
    expect(find.textContaining('Quando você adotar'), findsOneWidget);
  });

  testWidgets('Cards aparecem quando há dados e mostram pendências',
      (tester) async {
    await tester.pumpWidget(_home([
      AnimalModel.fromJson({'id': 1, 'name': 'Bolt'})
    ], [
      _m('m1', 'PENDING', DateTime.now().add(const Duration(days: 5)))
    ]));
    await tester.pumpAndSettle();
    expect(find.text('Meus Animais'), findsOneWidget);
    expect(find.text('Monitoramentos'), findsOneWidget);
    expect(find.text('1 monitoramento aguardando envio'), findsOneWidget);
  });

  testWidgets('Só monitoramento: card de animais fica oculto', (tester) async {
    await tester.pumpWidget(_home([], [_m('m1', 'APPROVED', null)]));
    await tester.pumpAndSettle();
    expect(find.text('Meus Animais'), findsNothing);
    expect(find.text('Monitoramentos'), findsOneWidget);
  });

  test('Lembretes: 3 dias antes, 1 antes, no dia e atrasos, às 9h', () {
    final now = DateTime(2026, 11, 10, 12);
    final plans = MonitoringReminders.plan(
        [_m('m1', 'PENDING', DateTime(2026, 11, 20, 15))], now);
    expect(plans.map((p) => p.when).toList(), [
      DateTime(2026, 11, 17, 9),
      DateTime(2026, 11, 19, 9),
      DateTime(2026, 11, 20, 9),
      DateTime(2026, 11, 21, 9),
      DateTime(2026, 11, 23, 9),
    ]);
    expect(plans.first.title, 'Monitoramento de Bolt');
    expect(plans.first.monitoringId, 'm1');
    expect(plans.map((p) => p.id).toSet().length, 5);
  });

  test('Lembretes ignoram enviados, aprovados e horários passados', () {
    final now = DateTime(2026, 11, 20, 12);
    final plans = MonitoringReminders.plan([
      _m('a', 'IN_REVIEW', DateTime(2026, 11, 25)),
      _m('b', 'APPROVED', DateTime(2026, 11, 25)),
      _m('c', 'REJECTED', DateTime(2026, 11, 20)),
    ], now);
    // Só o rejeitado (pode reenviar): restam os avisos de atraso.
    expect(plans.map((p) => p.when).toList(),
        [DateTime(2026, 11, 21, 9), DateTime(2026, 11, 23, 9)]);
  });
}
