import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:apasbac_app/core/theme/app_theme.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_forms.dart';
import 'package:apasbac_app/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets(
      'Settings show readable units and open the correct editor on a small screen',
      (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        configsProvider.overrideWith((ref) async => [
              {
                'key': 'monitoring_period_unit',
                'value': 'MONTHS',
                'description': ''
              },
              {
                'key': 'apasbac_email',
                'value': 'contato@example.com',
                'description': ''
              },
            ])
      ],
      child: MaterialApp(
          theme: buildAppTheme(), home: const Scaffold(body: ConfigsTab())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Meses'), findsOneWidget);
    expect(find.text('MONTHS'), findsNothing);
    expect(find.text('Contato da APASBAC'), findsOneWidget);
    await tester.tap(find.text('Unidade do intervalo'));
    await tester.pumpAndSettle();
    expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
    expect(find.text('Salvar alteração'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('Login remains usable with larger text on a narrow screen',
      (tester) async {
    tester.view.physicalSize = const Size(320, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(ProviderScope(
        child: MaterialApp(
      theme: buildAppTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: const LoginScreen(),
    )));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Entrar'));
    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Mostrar senha'), findsOneWidget);
  });
}
