import 'package:apasbac_app/core/models/monitoring_model.dart';
import 'package:apasbac_app/features/monitoring/presentation/widgets/media_gallery.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const photos = [
  MonitoringMedia(
      id: '1',
      url: 'https://res.cloudinary.com/x/image/upload/v1/a.jpg',
      type: 'IMAGE'),
  MonitoringMedia(
      id: '2',
      url: 'https://res.cloudinary.com/x/image/upload/v1/b.jpg',
      type: 'IMAGE'),
  MonitoringMedia(
      id: '3',
      url: 'https://res.cloudinary.com/x/image/upload/v1/c.jpg',
      type: 'IMAGE'),
];

void main() {
  testWidgets('desliza entre as fotos, mostra contador e fecha',
      (tester) async {
    await tester
        .pumpWidget(const MaterialApp(home: MediaViewerPage(medias: photos)));
    await tester.pump();
    expect(find.text('1 de 3'), findsOneWidget);
    await tester.fling(find.byType(PageView), const Offset(-400, 0), 1500);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('2 de 3'), findsOneWidget);
    // Toque esconde os controles; outro toque mostra de novo.
    await tester.tapAt(const Offset(400, 300));
    await tester.pump(const Duration(milliseconds: 500));
    final opacity = tester.widget<AnimatedOpacity>(find
        .ancestor(
            of: find.text('2 de 3'), matching: find.byType(AnimatedOpacity))
        .first);
    expect(opacity.opacity, 0);
    await tester.tap(find.byTooltip('Fechar'), warnIfMissed: false);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });

  testWidgets('seção mostra resumo e abre o visualizador', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: MonitoringMediaSection(medias: photos)))));
    expect(find.textContaining('3 fotos'), findsOneWidget);
    await tester.tap(find.byType(InkWell).first);
    await tester.pumpAndSettle(const Duration(milliseconds: 100));
    expect(find.text('1 de 3'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(minutes: 1));
  });
}
