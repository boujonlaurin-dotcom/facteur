import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:facteur/features/flux_continu/widgets/edition_date_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Future<ProviderContainer> pumpStrip(WidgetTester tester) async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [FacteurPalettes.light]),
          home: const Scaffold(body: EditionDateStrip()),
        ),
      ),
    );
    return container;
  }

  testWidgets('rend les pills Cette semaine / Aujourd\'hui / Hier', (
    tester,
  ) async {
    await pumpStrip(tester);
    expect(find.text('Cette semaine'), findsOneWidget);
    expect(find.text('Aujourd’hui'), findsOneWidget);
    expect(find.text('Hier'), findsOneWidget);
  });

  testWidgets('tap « Hier » → sélection = jour de la veille', (tester) async {
    final container = await pumpStrip(tester);
    await tester.tap(find.text('Hier'));
    await tester.pump();

    final sel = container.read(selectedEditionDateProvider);
    expect(sel, isA<EditionPastDay>());
    final yesterday = editionTodayDate().subtract(const Duration(days: 1));
    expect(editionDayKey((sel as EditionPastDay).date), editionDayKey(yesterday));
  });

  testWidgets('tap « Cette semaine » → sélection = EditionWeek', (tester) async {
    final container = await pumpStrip(tester);
    await tester.tap(find.text('Cette semaine'));
    await tester.pump();
    expect(container.read(selectedEditionDateProvider), isA<EditionWeek>());
  });

  testWidgets('la pill sélectionnée est en gras (Aujourd\'hui par défaut)', (
    tester,
  ) async {
    await pumpStrip(tester);
    final today = tester.widget<Text>(find.text('Aujourd’hui'));
    final hier = tester.widget<Text>(find.text('Hier'));
    expect(today.style?.fontWeight, FontWeight.w700); // sélectionnée
    expect(hier.style?.fontWeight, FontWeight.w500); // non sélectionnée
  });
}
