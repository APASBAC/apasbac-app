import 'package:apasbac_app/core/models/monitoring_model.dart';
import 'package:apasbac_app/core/models/user_model.dart';
import 'package:apasbac_app/core/services/monitoring_service.dart';
import 'package:apasbac_app/core/theme/app_theme.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_forms.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_screen.dart';
import 'package:apasbac_app/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Auth extends AuthNotifier {
  _Auth(this.role);
  final String role;
  @override
  Future<UserModel?> build() async => UserModel(
      id: 'a', fullName: 'Equipe', email: 'e@x', phone: '', role: role);
}

final _m = MonitoringModel.fromJson({
  'id': 'm1',
  'animalId': 1,
  'status': 'IN_REVIEW',
  'user': {'id': 'u2', 'fullName': 'Ana Lima'},
  'animal': {'id': 1, 'name': 'Bolt'},
  'imageUrls': ['https://res.cloudinary.com/x/image/upload/v1/a.jpg'],
});

Widget _app(String role, List<RequestOptions> calls) {
  final dio = Dio()
    ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
      calls.add(o);
      h.resolve(Response(
          requestOptions: o, statusCode: 200, data: {'success': true}));
    }));
  return ProviderScope(overrides: [
    authProvider.overrideWith(() => _Auth(role)),
    monitoringServiceProvider.overrideWithValue(MonitoringService(api: dio)),
    myMonitoringsProvider.overrideWith((ref) async => [_m]),
    adminAnimalsProvider.overrideWith((ref) async => []),
    adminUsersProvider.overrideWith((ref) async => []),
    configsProvider.overrideWith((ref) async => []),
  ], child: MaterialApp(theme: buildAppTheme(), home: const AdminScreen()));
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('Admin apaga monitoramento depois de confirmar', (tester) async {
    final calls = <RequestOptions>[];
    await tester.pumpWidget(_app('ADMIN', calls));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Apagar monitoramento'));
    await tester.pumpAndSettle();
    expect(find.text('Apagar monitoramento?'), findsOneWidget);
    expect(find.textContaining('as fotos e o vídeo'), findsOneWidget);
    // Cancelar não apaga nada.
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(calls, isEmpty);
    await tester.tap(find.byTooltip('Apagar monitoramento'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apagar'));
    await tester.pumpAndSettle();
    expect(calls.single.method, 'DELETE');
    expect(calls.single.path, '/monitoring/m1');
    expect(find.text('Monitoramento de Bolt apagado.'), findsOneWidget);
  });

  testWidgets('Equipe (STAFF) não vê o botão de apagar', (tester) async {
    await tester.pumpWidget(_app('STAFF', []));
    await tester.pumpAndSettle();
    expect(find.text('Bolt'), findsOneWidget);
    expect(find.byTooltip('Apagar monitoramento'), findsNothing);
  });
}
