import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_coverage.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/widgets/source_detail_modal.dart';

class _FakeUserSourcesNotifier extends UserSourcesNotifier {
  _FakeUserSourcesNotifier(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

class _FakeUserSourcesStateNotifier extends UserSourcesStateNotifier {
  _FakeUserSourcesStateNotifier(this._initial);
  final UserSourcesState _initial;

  @override
  Future<UserSourcesState> build() async => _initial;
}

const _emptyState = UserSourcesState(
  sources: [],
  favorites: [],
  favoriteCount: 0,
  favoriteCap: 5,
);

Widget _wrap({
  required Source source,
  SourceCoverage? coverage,
  List<SmartSearchRecentItem>? recentArticles,
  bool? isSelectedOverride,
  UserSourcesState state = _emptyState,
}) {
  return ProviderScope(
    overrides: [
      userSourcesProvider.overrideWith(() => _FakeUserSourcesNotifier([source])),
      userSourcesStateProvider
          .overrideWith(() => _FakeUserSourcesStateNotifier(state)),
      sourceCoverageProvider(source.id).overrideWith(
        (_) async =>
            coverage ?? const SourceCoverage(periodLabel: '', totalCount: 0),
      ),
      sourceRecentArticlesProvider(source.id).overrideWith(
        (_) async => recentArticles ?? const <SmartSearchRecentItem>[],
      ),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SourceDetailModal(
          source: source,
          onToggleTrust: () {},
          onToggleMute: () {},
          isSelectedOverride: isSelectedOverride,
        ),
      ),
    ),
  );
}

void main() {
  group('SourceDetailModal — header & layout', () {
    testWidgets('renders name, domain, follower signal and description',
        (tester) async {
      final source = Source(
        id: 's1',
        name: 'Le Monde',
        url: 'https://www.lemonde.fr',
        type: SourceType.article,
        description: 'Quotidien de référence.',
        followerCount: 1240,
      );

      await tester.pumpWidget(_wrap(source: source));
      await tester.pumpAndSettle();

      expect(find.text('Le Monde'), findsOneWidget);
      expect(find.text('lemonde.fr'), findsOneWidget);
      expect(find.text('Quotidien de référence.'), findsOneWidget);
      // Follower count uses narrow no-break space thousands separator.
      expect(find.textContaining('lecteurs'), findsOneWidget);
    });
  });

  group('SourceDetailModal — évaluation (cas Le Monde : complète + premium)',
      () {
    testWidgets('eval is collapsed by default, expands on tap with gauges',
        (tester) async {
      final source = Source(
        id: 'monde',
        name: 'Le Monde',
        url: 'https://lemonde.fr',
        type: SourceType.article,
        reliabilityScore: 'high',
        biasStance: 'center',
        scoreIndependence: 0.55,
        scoreRigor: 0.85,
        scoreUx: 0.70,
      );

      await tester.pumpWidget(_wrap(source: source));
      await tester.pumpAndSettle();

      // Collapsed: header title + reliability pill visible, gauges hidden.
      expect(find.text('Évaluation Facteur'), findsOneWidget);
      expect(find.text('Solide'), findsOneWidget);
      expect(find.text('Indépendance'), findsNothing);

      // Expand.
      await tester.tap(find.text('Évaluation Facteur'));
      await tester.pumpAndSettle();

      expect(find.text('Indépendance'), findsOneWidget);
      expect(find.text('Rigueur'), findsOneWidget);
      expect(find.text('Accessibilité'), findsOneWidget);
      // Gauge words derived by thresholds.
      expect(find.text('Correcte'), findsOneWidget); // 0.55
      expect(find.text('Élevée'), findsOneWidget); // 0.85
      expect(find.text('Bonne'), findsOneWidget); // 0.70
      expect(find.text('Voir la méthodologie'), findsOneWidget);
    });

    testWidgets('premium block always visible when premiumConnection != null '
        'even when not followed', (tester) async {
      final source = Source(
        id: 'monde',
        name: 'Le Monde',
        type: SourceType.article,
        isTrusted: false,
        premiumConnection: const PremiumConnection(
          loginUrl: 'https://lemonde.fr/login',
          testUrl: 'https://lemonde.fr/test',
          isGeneric: true,
        ),
      );

      await tester.pumpWidget(_wrap(source: source));
      await tester.pumpAndSettle();

      expect(find.text('Gestion de la source'), findsOneWidget);
      expect(find.text('Associer mon abonnement'), findsOneWidget);
    });
  });

  group('SourceDetailModal — cas Reporterre (jauge null + reco perso)', () {
    testWidgets('hides null gauge and shows collapsible reco perso',
        (tester) async {
      final source = Source(
        id: 'reporterre',
        name: 'Reporterre',
        type: SourceType.article,
        reliabilityScore: 'high',
        biasStance: 'left',
        scoreIndependence: 0.92,
        scoreRigor: 0.72,
        scoreUx: null, // accessibilité absente → jauge masquée
        recommendedBy: 'Camille',
        recommendationReason: 'Le seul média qui prend le temps du terrain.',
      );

      await tester.pumpWidget(_wrap(source: source));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Évaluation Facteur'));
      await tester.pumpAndSettle();

      expect(find.text('Indépendance'), findsOneWidget);
      expect(find.text('Rigueur'), findsOneWidget);
      // Null gauge hidden.
      expect(find.text('Accessibilité'), findsNothing);

      // Reco perso collapsed: label visible, quote hidden.
      expect(find.text('Recommandé par Camille'), findsOneWidget);
      expect(
        find.text('Le seul média qui prend le temps du terrain.'),
        findsNothing,
      );

      // Expand reco perso.
      await tester.tap(find.text('Recommandé par Camille'));
      await tester.pumpAndSettle();
      expect(
        find.text('Le seul média qui prend le temps du terrain.'),
        findsOneWidget,
      );
    });
  });

  group('SourceDetailModal — cas Le Pli (pas d\'articles / pas de scores)',
      () {
    testWidgets('shows "Pas encore évaluée" and articles empty-state',
        (tester) async {
      final source = Source(
        id: 'pli',
        name: 'Le Pli',
        type: SourceType.article,
        // no reliability, no scores
      );

      await tester.pumpWidget(_wrap(source: source, recentArticles: const []));
      await tester.pumpAndSettle();

      expect(find.text('Pas encore évaluée'), findsOneWidget);
      expect(find.text('Derniers articles'), findsOneWidget);
      expect(find.text('Rien publié ces 7 derniers jours.'), findsOneWidget);
    });
  });

  group('SourceDetailModal — couverture', () {
    testWidgets('renders coverage bars + caption when rows present',
        (tester) async {
      final source = Source(id: 'monde', name: 'Le Monde', type: SourceType.article);
      const coverage = SourceCoverage(
        periodLabel: '30 derniers jours',
        totalCount: 3012,
        caption: '3 012 articles publiés sur la période',
        rows: [
          CoverageRow(theme: 'politics', count: 1024, pct: 34),
          CoverageRow(theme: 'economy', count: 660, pct: 22),
          CoverageRow(theme: 'autres', count: 630, pct: 21),
        ],
      );

      await tester.pumpWidget(_wrap(source: source, coverage: coverage));
      await tester.pumpAndSettle();

      expect(find.text('Couverture par thèmes'), findsOneWidget);
      expect(find.text('30 derniers jours'), findsOneWidget);
      expect(find.text('Politique'), findsOneWidget);
      expect(find.text('Économie'), findsOneWidget);
      expect(find.text('Autres'), findsOneWidget);
      expect(
          find.text('3 012 articles publiés sur la période'), findsOneWidget);
    });

    testWidgets('hides coverage section when rows empty', (tester) async {
      final source = Source(id: 'x', name: 'X', type: SourceType.article);
      await tester.pumpWidget(_wrap(
        source: source,
        coverage: const SourceCoverage(
          periodLabel: '30 derniers jours',
          totalCount: 0,
          rows: [],
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('Couverture par thèmes'), findsNothing);
    });
  });

  group('SourceDetailModal — articles & réglages conditionnels', () {
    testWidgets('renders up to 3 article cards with theme tag', (tester) async {
      final source = Source(id: 'monde', name: 'Le Monde', type: SourceType.article);
      final recent = [
        const SmartSearchRecentItem(title: 'Article A', theme: 'politics'),
        const SmartSearchRecentItem(title: 'Article B', theme: 'economy'),
        const SmartSearchRecentItem(title: 'Article C'),
        const SmartSearchRecentItem(title: 'Article D'),
      ];

      await tester.pumpWidget(_wrap(source: source, recentArticles: recent));
      await tester.pumpAndSettle();

      expect(find.text('Article A'), findsOneWidget);
      expect(find.text('Article B'), findsOneWidget);
      expect(find.text('Article C'), findsOneWidget);
      // Only 3 shown.
      expect(find.text('Article D'), findsNothing);
    });

    testWidgets('settings (priority pill) hidden when NOT followed',
        (tester) async {
      final notFollowed =
          Source(id: 'a', name: 'A', type: SourceType.article, isTrusted: false);
      await tester.pumpWidget(_wrap(source: notFollowed));
      await tester.pumpAndSettle();
      expect(find.text('Réglages de suivi'), findsNothing);
    });

    testWidgets('settings (priority pill) shown when followed', (tester) async {
      final followed =
          Source(id: 'b', name: 'B', type: SourceType.article, isTrusted: true);
      await tester.pumpWidget(_wrap(source: followed));
      await tester.pumpAndSettle();
      expect(find.text('Réglages de suivi'), findsOneWidget);
      expect(find.text('Priorité dans ton flux'), findsOneWidget);
    });
  });

  group('SourceDetailModal — actions & mute toggle', () {
    testWidgets('primary action shows "Suivre {nom}" when not followed',
        (tester) async {
      final notFollowed = Source(
          id: 'a', name: 'Mediapart', type: SourceType.article, isTrusted: false);
      await tester.pumpWidget(_wrap(source: notFollowed));
      await tester.pumpAndSettle();
      expect(find.text('Suivre Mediapart'), findsOneWidget);
    });

    testWidgets('primary action shows "Suivie" when followed', (tester) async {
      final followed = Source(
          id: 'b', name: 'Mediapart', type: SourceType.article, isTrusted: true);
      await tester.pumpWidget(_wrap(source: followed));
      await tester.pumpAndSettle();
      expect(find.text('Suivie'), findsOneWidget);
    });

    testWidgets('onboarding override uses selection labels', (tester) async {
      final source = Source(id: 'c', name: 'Le Pli', type: SourceType.article);
      await tester.pumpWidget(
        _wrap(source: source, isSelectedOverride: false),
      );
      await tester.pumpAndSettle();
      expect(find.text('Sélectionner cette source'), findsOneWidget);
    });

    testWidgets('mute button shows "Masquer cette source" when not muted',
        (tester) async {
      final notMuted =
          Source(id: 'd', name: 'D', type: SourceType.article, isMuted: false);
      await tester.pumpWidget(_wrap(source: notMuted));
      await tester.pumpAndSettle();
      expect(find.text('Masquer cette source'), findsOneWidget);
    });

    testWidgets('mute button shows "Source masquée" when muted', (tester) async {
      final muted =
          Source(id: 'e', name: 'E', type: SourceType.article, isMuted: true);
      await tester.pumpWidget(_wrap(source: muted));
      await tester.pumpAndSettle();
      expect(find.text('Source masquée'), findsOneWidget);
    });
  });
}
