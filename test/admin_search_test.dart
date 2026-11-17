import 'package:apasbac_app/core/models/animal_model.dart';
import 'package:apasbac_app/core/models/monitoring_model.dart';
import 'package:apasbac_app/core/models/user_model.dart';
import 'package:apasbac_app/core/services/animal_service.dart';
import 'package:apasbac_app/core/theme/app_theme.dart';
import 'package:apasbac_app/core/widgets/search_field.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_forms.dart';
import 'package:apasbac_app/features/admin/presentation/screens/admin_screen.dart';
import 'package:apasbac_app/providers.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _Admin extends AuthNotifier {
  @override
  Future<UserModel?> build() async => const UserModel(
      id: 'admin',
      fullName: 'Admin',
      phone: '',
      email: 'admin@apasbac.org',
      role: 'ADMIN');
}

AnimalModel _animal(int id, String name,
        {bool adopted = false, String? tutor}) =>
    AnimalModel.fromJson({
      'id': id,
      'name': name,
      'breed': 'SRD',
      'sex': 'MALE',
      'size': 'SMALL',
      'isAdopted': adopted,
      if (adopted) 'adoptedById': 'u-$id',
      if (adopted) 'adoptedBy': {'id': 'u-$id', 'fullName': tutor},
    });

const _users = [
  UserModel(
      id: 'u1',
      fullName: 'João Pereira',
      email: 'joao@ex.com',
      phone: '44 99999-1111',
      role: 'USER'),
  UserModel(
      id: 'u2',
      fullName: 'Ana Lima',
      email: 'ana@ex.com',
      phone: '44 98888-2222',
      role: 'TUTOR'),
];

Widget _app() => ProviderScope(overrides: [
      authProvider.overrideWith(_Admin.new),
      myMonitoringsProvider.overrideWith((ref) async => [
            MonitoringModel.fromJson({
              'id': 'm1',
              'animalId': 1,
              'status': 'IN_REVIEW',
              'user': {
                'id': 'u2',
                'fullName': 'Ana Lima',
                'email': 'ana@ex.com'
              },
              'animal': {'id': 1, 'name': 'Bolt'},
            }),
            MonitoringModel.fromJson({
              'id': 'm2',
              'animalId': 2,
              'status': 'PENDING',
              'user': {'id': 'u3', 'fullName': 'Carlos Souza'},
              'animal': {'id': 2, 'name': 'Mel'},
            }),
          ]),
      adminAnimalsProvider.overrideWith((ref) async => [
            _animal(1, 'Bolt', adopted: true, tutor: 'Ana Lima'),
            _animal(2, 'Mel', adopted: true, tutor: 'Carlos Souza'),
            _animal(3, 'Pipoca'),
            _animal(4, 'Thor'),
          ]),
      adminUsersProvider.overrideWith((ref) async => _users),
      configsProvider.overrideWith((ref) async => []),
    ], child: MaterialApp(theme: buildAppTheme(), home: const AdminScreen()));

void main() {
  test('Busca ignora acentos, maiúsculas e pontuação de telefone', () {
    expect(matchesSearch('joao', ['João Pereira']), isTrue);
    expect(matchesSearch('PEREIRA jo', ['João Pereira']), isTrue);
    expect(matchesSearch('999991111', ['44 99999-1111']), isTrue);
    expect(matchesSearch('maria', ['João Pereira']), isFalse);
  });

  testWidgets('Monitoramentos filtram pelo nome do tutor', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    expect(find.text('Bolt'), findsOneWidget);
    expect(find.text('Mel'), findsOneWidget);
    await tester.enterText(find.byType(TextField).first, 'carlos');
    await tester.pumpAndSettle();
    expect(find.text('Bolt'), findsNothing);
    expect(find.text('Mel'), findsOneWidget);
  });

  testWidgets('Aba Animais lista todos e busca pelo tutor', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Animais'));
    await tester.pumpAndSettle();
    for (final name in ['Bolt', 'Mel', 'Pipoca', 'Thor']) {
      expect(find.text(name), findsOneWidget);
    }
    await tester.enterText(find.byType(TextField).first, 'ana lima');
    await tester.pumpAndSettle();
    expect(find.text('Bolt'), findsOneWidget);
    expect(find.text('Pipoca'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Adoção e usuários têm busca de usuário', (tester) async {
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adoções'));
    await tester.pumpAndSettle();
    expect(find.text('Pipoca'), findsOneWidget);
    expect(find.text('Bolt'), findsNothing);
    await tester.tap(find.text('Adotar').first);
    await tester.pumpAndSettle();
    expect(find.text('João Pereira'), findsOneWidget);
    expect(find.text('Ana Lima'), findsOneWidget);
    await tester.enterText(
        find.widgetWithText(
            TextField, 'Buscar por nome, e-mail, telefone ou CPF'),
        'joao');
    await tester.pumpAndSettle();
    expect(find.text('João Pereira'), findsOneWidget);
    expect(find.text('Ana Lima'), findsNothing);
    await tester.tap(find.text('João Pereira'));
    await tester.pumpAndSettle();
    expect(find.text('Confirmar adoção'), findsOneWidget);
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Usuários'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'ana@');
    await tester.pumpAndSettle();
    expect(find.text('Ana Lima'), findsOneWidget);
    expect(find.text('João Pereira'), findsNothing);
  });

  testWidgets('Novo monitoramento busca animal pelo tutor', (tester) async {
    await tester.pumpWidget(ProviderScope(overrides: [
      authProvider.overrideWith(_Admin.new),
      adminAnimalsProvider.overrideWith((ref) async => [
            _animal(1, 'Bolt', adopted: true, tutor: 'Ana Lima'),
            _animal(2, 'Mel', adopted: true, tutor: 'Carlos Souza'),
          ]),
    ], child: const MaterialApp(home: MonitoringCreateScreen())));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'carlos');
    await tester.pumpAndSettle();
    expect(find.text('Mel (#2)'), findsOneWidget);
    expect(find.text('Bolt (#1)'), findsNothing);
  });

  test('Lista de animais percorre todas as páginas', () async {
    final pages = <int>[];
    final dio = Dio()
      ..interceptors.add(InterceptorsWrapper(onRequest: (o, h) {
        final page = o.queryParameters['page'] as int;
        pages.add(page);
        final count = page < 3 ? 100 : 7;
        h.resolve(Response(requestOptions: o, statusCode: 200, data: {
          'data': {
            'data': [
              for (var i = 0; i < count; i++)
                {'id': page * 1000 + i, 'name': 'A'}
            ]
          }
        }));
      }));
    final all = await AnimalService(api: dio).getAllAnimals();
    expect(all.length, 207);
    expect(pages, [1, 2, 3]);
  });
}
