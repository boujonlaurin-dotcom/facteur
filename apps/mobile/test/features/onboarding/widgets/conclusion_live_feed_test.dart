import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/onboarding/onboarding_strings.dart';
import 'package:facteur/features/onboarding/widgets/conclusion_live_feed.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_recent_items.dart';

SourceRecentItems _entry(String id, String name, List<String> titles) {
  return SourceRecentItems(
    sourceId: id,
    name: name,
    items: [for (final t in titles) SmartSearchRecentItem(title: t)],
  );
}

void main() {
  Widget buildTestWidget(List<SourceRecentItems> entries) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: ConclusionLiveFeed(entries: entries),
      ),
    );
  }

  testWidgets('révèle les titres au rythme du timer, compteur synchrone',
      (tester) async {
    await tester.pumpWidget(buildTestWidget([
      _entry('s1', 'Le Monde', ['LM un', 'LM deux']),
      _entry('s2', 'Libé', ['LB un']),
    ]));

    // t0 : rien de révélé.
    expect(find.text(OnboardingStrings.conclusionLiveCounter(0, 2)),
        findsOneWidget);
    expect(find.text('LM un'), findsNothing);

    // 1er tick (800ms) : premier titre (round-robin : LM un).
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('LM un'), findsOneWidget);

    // 2e tick : LB un (entrelacé), 3e tick : LM deux.
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('LB un'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('LM deux'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text(OnboardingStrings.conclusionLiveCounter(3, 2)),
        findsOneWidget);
  });

  testWidgets('didUpdateWidget : nouvelles entrées en fin de file, sans reset',
      (tester) async {
    await tester.pumpWidget(buildTestWidget([
      _entry('s1', 'Le Monde', ['LM un']),
    ]));
    await tester.pump(const Duration(milliseconds: 800));
    expect(find.text('LM un'), findsOneWidget);

    // L'endpoint répond : s1 enrichi (dédup du titre déjà vu) + s2 ajouté.
    await tester.pumpWidget(buildTestWidget([
      _entry('s1', 'Le Monde', ['LM un', 'LM deux']),
      _entry('s2', 'Libé', ['LB un']),
    ]));

    // Le titre déjà révélé reste affiché (pas de réordonnancement).
    expect(find.text('LM un'), findsOneWidget);

    // Les nouveaux arrivent à la suite.
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpAndSettle();
    expect(find.text('LM deux'), findsOneWidget);
    expect(find.text('LB un'), findsOneWidget);
    expect(find.text(OnboardingStrings.conclusionLiveCounter(3, 2)),
        findsOneWidget);
  });

  testWidgets('reduced motion : tout est révélé immédiatement',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: ConclusionLiveFeed(entries: [
            _entry('s1', 'Le Monde', ['LM un', 'LM deux']),
          ]),
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('LM un'), findsOneWidget);
    expect(find.text('LM deux'), findsOneWidget);
    expect(find.text(OnboardingStrings.conclusionLiveCounter(2, 1)),
        findsOneWidget);
  });

  testWidgets('strip de logos : cap à 8 + badge « +N »', (tester) async {
    final entries = [
      for (var i = 0; i < 10; i++) _entry('s$i', 'Source $i', ['T$i']),
    ];
    await tester.pumpWidget(buildTestWidget(entries));
    await tester.pumpAndSettle(const Duration(milliseconds: 200));

    expect(find.text('+2'), findsOneWidget);
  });
}
