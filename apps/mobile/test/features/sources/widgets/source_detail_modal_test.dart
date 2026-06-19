import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/smart_search_result.dart';
import 'package:facteur/features/sources/models/source_coverage.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/models/source_profile.dart';
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

Content _article(String id, String title, {String? theme}) {
  return Content(
    id: id,
    title: title,
    url: 'https://example.com/$id',
    contentType: ContentType.article,
    publishedAt: DateTime(2026, 6, 14),
    topics: theme != null ? [theme] : const [],
    source: Source(id: 's', name: 'Le Monde', type: SourceType.article),
  );
}

/// Mode normal : la fiche s'alimente du profil unifié [sourceProfileProvider].
/// [profileError] simule une panne réseau (→ fallback statique).
/// [recentItems] non-null bascule en mode smart-search (couverture via
/// [sourceCoverageProvider], cartes minimales préchargées).
Widget _wrap({
  required Source source,
  SourceProfile? profile,
  Object? profileError,
  SourceCoverage? coverage,
  List<SmartSearchRecentItem>? recentItems,
  bool? isSelectedOverride,
  SourceArticleOpener? articleOpener,
  UserSourcesState state = _emptyState,
}) {
  return ProviderScope(
    overrides: [
      userSourcesProvider.overrideWith(
        () => _FakeUserSourcesNotifier([source]),
      ),
      userSourcesStateProvider.overrideWith(
        () => _FakeUserSourcesStateNotifier(state),
      ),
      displayModeSpecProvider.overrideWith((ref) => DisplayModeSpec.normal),
      sourceCoverageProvider(source.id).overrideWith(
        (_) async =>
            coverage ?? const SourceCoverage(periodLabel: '', totalCount: 0),
      ),
      sourceProfileProvider(source.id).overrideWith((_) async {
        if (profileError != null) throw profileError;
        return profile ?? const SourceProfile();
      }),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SourceDetailModal(
          source: source,
          onToggleTrust: () {},
          onToggleMute: () {},
          isSelectedOverride: isSelectedOverride,
          recentItems: recentItems,
          articleOpener: articleOpener,
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('SourceDetailModal — header & layout', () {
    testWidgets('renders name, domain, follower signal and description', (
      tester,
    ) async {
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

    testWidgets('frequency chip rendered from profile (header signals)', (
      tester,
    ) async {
      final source = Source(
        id: 's1',
        name: 'Le Monde',
        type: SourceType.article,
      );
      // 60 articles, fenêtre 30 j → 2/jour → wording naturel.
      const profile = SourceProfile(articles30d: 60);

      await tester.pumpWidget(_wrap(source: source, profile: profile));
      await tester.pumpAndSettle();

      expect(find.text('quelques articles par jour'), findsOneWidget);
    });
  });

  group(
    'SourceDetailModal — évaluation (cas Le Monde : complète + premium)',
    () {
      testWidgets('eval is collapsed by default then shows A-E badges', (
        tester,
      ) async {
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

        // Collapsed by default: title, subtitle and summary visible.
        expect(find.text('Évaluation Facteur'), findsOneWidget);
        expect(find.text('à titre indicatif'), findsOneWidget);
        expect(find.text('Solide'), findsWidgets);
        expect(find.text('Indépendance'), findsNothing);
        expect(find.text('Rigueur'), findsNothing);
        expect(find.text('Accessibilité'), findsNothing);

        await tester.tap(find.text('Évaluation Facteur'));
        await tester.pumpAndSettle();

        // The reliability scale is no longer inline (no duplicate): the eval
        // value 'Solide' appears exactly once (in the collapsed summary).
        expect(find.text('Solide'), findsOneWidget);
        expect(find.text('Échelle de fiabilité'), findsNothing);
        expect(find.text('Indépendance'), findsOneWidget);
        expect(find.text('Rigueur'), findsOneWidget);
        expect(find.text('Accessibilité'), findsOneWidget);
        // Grades derived by thresholds: 0.55=C, 0.85=A, 0.70=B.
        expect(find.text('A'), findsOneWidget);
        expect(find.text('B'), findsOneWidget);
        expect(find.text('C'), findsOneWidget);
        expect(find.text('Voir la méthodologie'), findsOneWidget);
      });

      testWidgets(
        'reliability (i) opens the scale sheet with the three explanations',
        (tester) async {
          final source = Source(
            id: 'monde',
            name: 'Le Monde',
            type: SourceType.article,
            reliabilityScore: 'high',
          );

          await tester.pumpWidget(_wrap(source: source));
          await tester.pumpAndSettle();

          // The (i) sits next to the reliability label in the collapsed summary.
          final infoIcon = find.bySemanticsLabel('Échelle de fiabilité');
          expect(infoIcon, findsOneWidget);

          await tester.tap(infoIcon);
          await tester.pumpAndSettle();

          // Sheet titled + 3 explanations.
          expect(find.text('Échelle de fiabilité'), findsOneWidget);
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText() == 'Solide = fiabilité élevée',
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText() ==
                      'Mitigée = points de vigilance',
            ),
            findsOneWidget,
          );
          expect(
            find.byWidgetPredicate(
              (widget) =>
                  widget is RichText &&
                  widget.text.toPlainText() == 'Fragile = prudence renforcée',
            ),
            findsOneWidget,
          );

          // The eval stays collapsed: tapping (i) did not reveal the badges.
          expect(find.text('Voir la méthodologie'), findsNothing);
        },
      );

      testWidgets(
          'premium block always visible when premiumConnection != null '
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
    },
  );

  group('SourceDetailModal — cas Reporterre (jauge null + reco perso)', () {
    testWidgets('hides null gauge and shows collapsible reco perso', (
      tester,
    ) async {
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

  group('SourceDetailModal — enrichissement via /profile (depuis le reader)', () {
    testWidgets(
      'light source (SourceMini) gains followers, scores and description '
      'once /profile responds',
      (tester) async {
        // SourceMini léger tel que sérialisé par le reader : ni lecteurs,
        // ni scores, ni description, éval inconnue.
        final light = Source(
          id: 'monde',
          name: 'Le Monde',
          type: SourceType.article,
        );
        // /profile renvoie la source complète.
        final profile = SourceProfile(
          source: Source(
            id: 'monde',
            name: 'Le Monde',
            type: SourceType.article,
            reliabilityScore: 'high',
            followerCount: 1240,
            description: 'Quotidien de référence.',
            scoreIndependence: 0.55,
            scoreRigor: 0.85,
            scoreUx: 0.70,
          ),
        );

        await tester.pumpWidget(_wrap(source: light, profile: profile));
        await tester.pumpAndSettle();

        // Signal lecteurs + description réapparaissent.
        expect(find.textContaining('lecteurs'), findsOneWidget);
        expect(find.text('Quotidien de référence.'), findsOneWidget);

        // L'éval enrichie expose les badges A-E une fois dépliée.
        await tester.tap(find.text('Évaluation Facteur'));
        await tester.pumpAndSettle();
        expect(find.text('Indépendance'), findsOneWidget);
        expect(find.text('Rigueur'), findsOneWidget);
        expect(find.text('Accessibilité'), findsOneWidget);
        // 0.85 → A, 0.70 → B, 0.55 → C.
        expect(find.text('A'), findsOneWidget);
        expect(find.text('B'), findsOneWidget);
        expect(find.text('C'), findsOneWidget);
      },
    );
  });

  group('SourceDetailModal — couverture (mode normal, profil unifié)', () {
    testWidgets('renders coverage bars + caption derived from articles_30d', (
      tester,
    ) async {
      final source = Source(
        id: 'monde',
        name: 'Le Monde',
        type: SourceType.article,
      );
      const profile = SourceProfile(
        articles30d: 3012,
        themeDistribution: [
          ThemeShare(theme: 'politics', count: 1024, share: 0.34),
          ThemeShare(theme: 'economy', count: 660, share: 0.22),
          ThemeShare(theme: 'autres', count: 630, share: 0.21),
        ],
      );

      await tester.pumpWidget(_wrap(source: source, profile: profile));
      await tester.pumpAndSettle();

      expect(find.text('Couverture par thèmes'), findsOneWidget);
      expect(find.text('30 derniers jours'), findsOneWidget);
      expect(find.text('Politique'), findsOneWidget);
      expect(find.text('Économie'), findsOneWidget);
      expect(find.text('Autres'), findsOneWidget);
      // Caption derived client-side, aligned with backend copy (U+202F milliers).
      expect(
        find.text('3\u202F012 articles publiés sur la période'),
        findsOneWidget,
      );
    });

    testWidgets('keeps top 3 themes and merges the rest into Autres', (
      tester,
    ) async {
      final source = Source(id: 'x', name: 'X', type: SourceType.article);
      const profile = SourceProfile(
        articles30d: 100,
        themeDistribution: [
          ThemeShare(theme: 'politics', count: 30, share: 0.30),
          ThemeShare(theme: 'economy', count: 25, share: 0.25),
          ThemeShare(theme: 'science', count: 20, share: 0.20),
          ThemeShare(theme: 'culture', count: 15, share: 0.15),
          ThemeShare(theme: 'other', count: 10, share: 0.10),
        ],
      );

      await tester.pumpWidget(_wrap(source: source, profile: profile));
      await tester.pumpAndSettle();

      expect(find.text('Politique'), findsOneWidget);
      expect(find.text('Économie'), findsOneWidget);
      expect(find.text('Culture'), findsNothing);
      expect(find.text('Autres'), findsOneWidget);
      expect(find.text('25 %'), findsWidgets);
    });

    testWidgets('hides coverage section when theme_distribution empty', (
      tester,
    ) async {
      final source = Source(id: 'x', name: 'X', type: SourceType.article);
      await tester.pumpWidget(
        _wrap(source: source, profile: const SourceProfile(articles30d: 0)),
      );
      await tester.pumpAndSettle();

      expect(find.text('Couverture par thèmes'), findsNothing);
    });
  });

  group('SourceDetailModal — articles (mode normal, cartes cliquables)', () {
    testWidgets('renders up to 3 FluxContinuArticleCard from recent_articles', (
      tester,
    ) async {
      final source = Source(
        id: 'monde',
        name: 'Le Monde',
        type: SourceType.article,
      );
      final profile = SourceProfile(
        recentArticles: [
          _article('a', 'Article A', theme: 'politics'),
          _article('b', 'Article B', theme: 'economy'),
          _article('c', 'Article C'),
          _article('d', 'Article D'),
        ],
      );

      await tester.pumpWidget(_wrap(source: source, profile: profile));
      await tester.pumpAndSettle();

      expect(find.text('Derniers articles'), findsOneWidget);
      expect(find.text('Article A'), findsOneWidget);
      expect(find.text('Article B'), findsOneWidget);
      expect(find.text('Article C'), findsOneWidget);
      // Only 3 shown (4th dropped).
      expect(find.text('Article D'), findsNothing);
    });

    testWidgets('articleOpener injecté ouvre sans GoRouter', (tester) async {
      final source = Source(
        id: 'monde',
        name: 'Le Monde',
        type: SourceType.article,
      );
      final opened = <String>[];
      final profile = SourceProfile(
        recentArticles: [_article('a', 'Article A', theme: 'politics')],
      );

      await tester.pumpWidget(
        _wrap(
          source: source,
          profile: profile,
          articleOpener: (_, article) => opened.add(article.id),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Article A'));
      await tester.pumpAndSettle();

      expect(opened, equals(['a']));
    });

    testWidgets('empty recent_articles → neutral empty card', (tester) async {
      final source = Source(id: 'x', name: 'X', type: SourceType.article);
      await tester.pumpWidget(
        _wrap(source: source, profile: const SourceProfile()),
      );
      await tester.pumpAndSettle();

      expect(find.text('Aucun article récent.'), findsOneWidget);
    });
  });

  group('SourceDetailModal — fallback réseau (/profile en erreur)', () {
    testWidgets(
      'error → identité/éval restent + zone articles propose un retry',
      (tester) async {
        final source = Source(
          id: 'monde',
          name: 'Le Monde',
          type: SourceType.article,
          reliabilityScore: 'high',
        );

        // /profile en erreur ET /coverage vide (pire cas réseau).
        await tester.pumpWidget(
          _wrap(source: source, profileError: Exception('network down')),
        );
        await tester.pumpAndSettle();

        // La fiche ne bloque jamais : identité + éval toujours là.
        expect(find.text('Le Monde'), findsOneWidget);
        expect(find.text('Évaluation Facteur'), findsOneWidget);
        // Couverture masquée (/coverage vide), mais la zone articles n'est plus
        // muette : message d'indisponibilité + bouton « Réessayer ».
        expect(find.text('Couverture par thèmes'), findsNothing);
        expect(find.text('Derniers articles'), findsOneWidget);
        expect(
          find.text('Contenu momentanément indisponible.'),
          findsOneWidget,
        );
        expect(find.text('Réessayer'), findsOneWidget);
      },
    );

    testWidgets(
      'error → couverture retombe sur /coverage (endpoint indépendant)',
      (tester) async {
        final source = Source(
          id: 'monde',
          name: 'Le Monde',
          type: SourceType.article,
        );
        const coverage = SourceCoverage(
          periodLabel: '30 derniers jours',
          totalCount: 100,
          caption: '100 articles publiés sur la période',
          rows: [CoverageRow(theme: 'politics', count: 100, pct: 100)],
        );

        // /profile KO mais /coverage OK → la couverture reste visible.
        await tester.pumpWidget(
          _wrap(
            source: source,
            profileError: Exception('network down'),
            coverage: coverage,
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Couverture par thèmes'), findsOneWidget);
        expect(find.text('Réessayer'), findsOneWidget);
      },
    );
  });

  group('SourceDetailModal — mode smart-search (recentItems préchargés)', () {
    testWidgets('renders minimal article cards + coverage from provider', (
      tester,
    ) async {
      final source = Source(
        id: 'monde',
        name: 'Le Monde',
        type: SourceType.article,
      );
      const coverage = SourceCoverage(
        periodLabel: '30 derniers jours',
        totalCount: 100,
        caption: '100 articles publiés sur la période',
        rows: [CoverageRow(theme: 'politics', count: 100, pct: 100)],
      );
      final recent = [
        const SmartSearchRecentItem(title: 'Article A', theme: 'politics'),
        const SmartSearchRecentItem(title: 'Article B'),
        const SmartSearchRecentItem(title: 'Article C'),
        const SmartSearchRecentItem(title: 'Article D'),
      ];

      await tester.pumpWidget(
        _wrap(source: source, coverage: coverage, recentItems: recent),
      );
      await tester.pumpAndSettle();

      expect(find.text('Politique'), findsWidgets);
      expect(find.text('Article A'), findsOneWidget);
      expect(find.text('Article B'), findsOneWidget);
      expect(find.text('Article C'), findsOneWidget);
      expect(find.text('Article D'), findsNothing);
    });
  });

  group('SourceDetailModal — réglages conditionnels', () {
    testWidgets('settings (priority pill) hidden when NOT followed', (
      tester,
    ) async {
      final notFollowed = Source(
        id: 'a',
        name: 'A',
        type: SourceType.article,
        isTrusted: false,
      );
      await tester.pumpWidget(_wrap(source: notFollowed));
      await tester.pumpAndSettle();
      expect(find.text('Réglages de suivi'), findsNothing);
    });

    testWidgets('settings (priority pill) shown when followed', (tester) async {
      final followed = Source(
        id: 'b',
        name: 'B',
        type: SourceType.article,
        isTrusted: true,
      );
      await tester.pumpWidget(_wrap(source: followed));
      await tester.pumpAndSettle();
      expect(find.text('Réglages de suivi'), findsOneWidget);
      expect(find.text('Priorité dans ton flux'), findsOneWidget);
    });
  });

  group('SourceDetailModal — actions & mute toggle', () {
    testWidgets('primary action shows "Suivre {nom}" when not followed', (
      tester,
    ) async {
      final notFollowed = Source(
        id: 'a',
        name: 'Mediapart',
        type: SourceType.article,
        isTrusted: false,
      );
      await tester.pumpWidget(_wrap(source: notFollowed));
      await tester.pumpAndSettle();
      expect(find.text('Suivre Mediapart'), findsOneWidget);
    });

    testWidgets('primary action shows "Suivie" when followed', (tester) async {
      final followed = Source(
        id: 'b',
        name: 'Mediapart',
        type: SourceType.article,
        isTrusted: true,
      );
      await tester.pumpWidget(_wrap(source: followed));
      await tester.pumpAndSettle();
      expect(find.text('Suivie'), findsOneWidget);
    });

    testWidgets('onboarding override uses selection labels', (tester) async {
      final source = Source(id: 'c', name: 'Le Pli', type: SourceType.article);
      await tester.pumpWidget(_wrap(source: source, isSelectedOverride: false));
      await tester.pumpAndSettle();
      expect(find.text('Sélectionner cette source'), findsOneWidget);
    });

    testWidgets('mute button shows "Masquer cette source" when not muted', (
      tester,
    ) async {
      final notMuted = Source(
        id: 'd',
        name: 'D',
        type: SourceType.article,
        isMuted: false,
      );
      await tester.pumpWidget(_wrap(source: notMuted));
      await tester.pumpAndSettle();
      expect(find.text('Masquer cette source'), findsOneWidget);
    });

    testWidgets('mute button shows "Source masquée" when muted', (
      tester,
    ) async {
      final muted = Source(
        id: 'e',
        name: 'E',
        type: SourceType.article,
        isMuted: true,
      );
      await tester.pumpWidget(_wrap(source: muted));
      await tester.pumpAndSettle();
      expect(find.text('Source masquée'), findsOneWidget);
    });
  });
}
