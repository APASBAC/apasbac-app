import 'package:apasbac_app/core/models/user_model.dart';
import 'package:apasbac_app/core/services/user_service.dart';
import 'package:apasbac_app/core/theme/app_theme.dart';
import 'package:apasbac_app/core/widgets/apasbac_loading.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_forms.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_screen.dart';
import 'package:apasbac_app/features/auth/presentation/screens/profile_screen.dart';
import 'package:apasbac_app/main.dart';
import 'package:apasbac_app/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class TestAuth extends AuthNotifier {
  @override
  Future<UserModel?> build() async => const UserModel(
      id: 'user-1',
      fullName: 'Maria Silva',
      phone: '44999999999',
      email: 'maria@example.com',
      role: 'ADMIN');
}

void main() {
  testWidgets(
      'Profile saves only editable fields and stays open after auth update',
      (tester) async {
    final requests = <RequestOptions>[];
    final api = Dio();
    api.interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
      requests.add(r);
      h.resolve(Response(requestOptions: r, statusCode: 200));
    }));
    await tester.pumpWidget(ProviderScope(overrides: [
      authProvider.overrideWith(TestAuth.new),
      userServiceProvider.overrideWithValue(UserService(api: api)),
    ], child: const ApasbacApp()));
    await tester.pumpAndSettle();
    expect(find.text('Abrir administração'), findsOneWidget);
    expect(find.text('Uma nova vida.\nUm cuidado para sempre.'), findsNothing);
    await tester.tap(find.byTooltip('Meu perfil'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextFormField).first, ' Maria Souza ');
    await tester.enterText(find.byType(TextFormField).last, '44988888888');
    await tester.ensureVisible(find.text('Salvar alterações'));
    await tester.tap(find.text('Salvar alterações'));
    await tester.pumpAndSettle();
    expect(requests.single.path, '/users/user-1');
    expect(requests.single.method, 'PATCH');
    expect(requests.single.data,
        {'fullName': 'Maria Souza', 'phone': '44988888888'});
    expect(find.byType(ProfileScreen), findsOneWidget);
    expect(find.text('Perfil atualizado.'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.byType(ProfileScreen), findsNothing);
  });

  testWidgets(
      'Creation actions are visible only in their own tabs, including empty lists',
      (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      authProvider.overrideWith(TestAuth.new),
      myMonitoringsProvider.overrideWith((ref) async => []),
      adminAnimalsProvider.overrideWith((ref) async => []),
      adminUsersProvider.overrideWith((ref) async => []),
      configsProvider.overrideWith((ref) async => []),
    ], child: MaterialApp(theme: buildAppTheme(), home: const AdminScreen())));
    await tester.pumpAndSettle();
    expect(find.text('Criar monitoramento'), findsOneWidget);
    expect(find.text('Cadastrar animal'), findsNothing);
    await tester.tap(find.text('Adoções'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastrar animal'), findsOneWidget);
    expect(find.text('Criar monitoramento'), findsNothing);
    await tester.tap(find.text('Usuários'));
    await tester.pumpAndSettle();
    expect(find.text('Cadastrar animal'), findsNothing);
    expect(find.text('Criar monitoramento'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Branded loading animates and respects reduced motion',
      (tester) async {
    Widget app(bool reduced) => MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: reduced),
            child: const Scaffold(body: ApasbacLoading())));
    await tester.pumpWidget(app(false));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Carregando'), findsOneWidget);
    expect(tester.binding.hasScheduledFrame, isTrue);
    await tester.pumpWidget(app(true));
    await tester.pumpAndSettle();
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(tester.takeException(), isNull);
  });

  test('Invalid profile data never reaches the API', () async {
    var called = false;
    final api = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (r, h) {
        called = true;
        h.resolve(Response(requestOptions: r, statusCode: 200));
      }));
    final service = UserService(api: api);
    await expectLater(
        service.updateProfile('1', fullName: '', phone: '44999999999'),
        throwsArgumentError);
    await expectLater(
        service.updateProfile('1', fullName: 'Maria', phone: '123'),
        throwsArgumentError);
    expect(called, isFalse);
  });
}
