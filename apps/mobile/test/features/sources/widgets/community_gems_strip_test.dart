import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/features/sources/widgets/community_gems_strip.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/config/theme.dart';

void main() {
  group('CommunityGemsStrip', () {
    final mockSources = [
      Source(id: '1', name: 'Le Monde', type: SourceType.article),
      Source(id: '2', name: 'Fireship', type: SourceType.youtube),
      Source(id: '3', name: 'r/france', type: SourceType.reddit),
    ];

    Widget buildHarness(List<Source> sources, {void Function(Source)? onTap, void Function(String)? onGem}) {
      return ProviderScope(
        overrides: [
          trendingSourcesProvider.overrideWith((_) async => sources),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: CommunityGemsStrip(
              onSourceTap: onTap ?? (_) {},
              onGemTap: onGem,
            ),
          ),
        ),
      );
    }

    testWidgets('header is visible and section is collapsed by default',
        (tester) async {
      await tester.pumpWidget(buildHarness(mockSources));
      await tester.pumpAndSettle();

      expect(find.text('Pépites de la communauté'), findsOneWidget);
      expect(find.text('Le Monde'), findsNothing);
    });

    testWidgets('expands and renders all sources when header tapped',
        (tester) async {
      await tester.pumpWidget(buildHarness(mockSources));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pépites de la communauté'));
      await tester.pumpAndSettle();

      expect(find.text('Le Monde'), findsOneWidget);
      expect(find.text('Fireship'), findsOneWidget);
      expect(find.text('r/france'), findsOneWidget);
    });

    testWidgets('shows empty message when expanded with no sources',
        (tester) async {
      await tester.pumpWidget(buildHarness(<Source>[]));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pépites de la communauté'));
      await tester.pumpAndSettle();

      expect(find.text('Aucune pépite pour le moment.'), findsOneWidget);
    });

    testWidgets('fires callbacks on gem tap', (tester) async {
      Source? tappedSource;
      String? tappedGemId;

      await tester.pumpWidget(buildHarness(
        mockSources,
        onTap: (s) => tappedSource = s,
        onGem: (id) => tappedGemId = id,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Pépites de la communauté'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Le Monde'));
      expect(tappedSource?.id, '1');
      expect(tappedGemId, '1');
    });
  });
}
