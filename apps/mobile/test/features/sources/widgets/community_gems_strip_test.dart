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

    testWidgets('renders sources horizontally when data loaded',
        (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingSourcesProvider.overrideWith((_) async => mockSources),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: Scaffold(
              body: CommunityGemsStrip(
                onSourceTap: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Le Monde'), findsOneWidget);
      expect(find.text('Fireship'), findsOneWidget);
      expect(find.text('r/france'), findsOneWidget);
    });

    testWidgets('displays section title', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingSourcesProvider.overrideWith((_) async => mockSources),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: Scaffold(
              body: CommunityGemsStrip(
                onSourceTap: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(find.text('Pepites de la communaute'), findsOneWidget);
    });

    testWidgets('shows empty message when no sources', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingSourcesProvider
                .overrideWith((_) async => <Source>[]),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: Scaffold(
              body: CommunityGemsStrip(
                onSourceTap: (_) {},
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Aucune pepite pour le moment.'), findsOneWidget);
    });

    testWidgets('fires callbacks on tap', (tester) async {
      Source? tappedSource;
      String? tappedGemId;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            trendingSourcesProvider.overrideWith((_) async => mockSources),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: Scaffold(
              body: CommunityGemsStrip(
                onSourceTap: (s) => tappedSource = s,
                onGemTap: (id) => tappedGemId = id,
              ),
            ),
          ),
        ),
      );

      await tester.pumpAndSettle();

      await tester.tap(find.text('Le Monde'));
      expect(tappedSource?.id, '1');
      expect(tappedGemId, '1');
    });
  });
}
