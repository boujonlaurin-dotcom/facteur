// PR « Sources dans la Tournée » — couverture des sections SOURCE de la Tournée
// composées par le FluxContinuNotifier : présence (kind=source), ordre
// (après les thèmes), dédup inter-sections, et état vide « toujours visible ».
import 'dart:io';

import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart'
    show kSectionMinItems;
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flux_continu_settle.dart';

class _MockDigestRepository extends Mock implements DigestRepository {}

class _MockFeedRepository extends Mock implements FeedRepository {}

class _MockFluxContinuRepository extends Mock
    implements FluxContinuRepository {}

class _StubEssentielRepository implements EssentielRepository {
  // Story 33.3 — « Plus d'articles ? » ne concerne pas ces tests ; le stub
  // renvoie « rien d'inédit » pour rester conforme à l'interface.
  @override
  Future<List<Map<String, dynamic>>?> fetchMore({
    required List<String> excludeIds,
    int limit = 2,
  }) async =>
      const [];

  @override
  Future<EssentielFetchResult?> fetch({bool? serein, DateTime? date}) async =>
      (articles: const <EssentielArticle>[], newSinceMorning: 0, carousel: null);

  // Story 33.1 — la collecte de tri n'a aucun effet sur ces tests ;
  // le stub l'accepte pour rester conforme a l'interface.
  @override
  Future<bool> postTriage({
    required String digestDate,
    required int slateSize,
    required List<Map<String, dynamic>> decisions,
  }) async =>
      true;
}

class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._initial);
  final UserInterestsState _initial;
  @override
  Future<UserInterestsState> build() async => _initial;
}

class _StubUserSourcesStateNotifier extends UserSourcesStateNotifier {
  _StubUserSourcesStateNotifier(this._initial);
  final UserSourcesState _initial;
  @override
  Future<UserSourcesState> build() async => _initial;
}

class _StubUserSourcesNotifier extends UserSourcesNotifier {
  _StubUserSourcesNotifier(this._initial);
  final List<Source> _initial;
  @override
  Future<List<Source>> build() async => _initial;
}

UserInterestsState _interestsState({List<FavoriteRef> favorites = const []}) {
  return UserInterestsState(
    themes: const [],
    customTopics: const [],
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 7,
  );
}

UserSourcesState _sourcesState({List<SourceFavoriteRef> favorites = const []}) {
  return UserSourcesState(
    sources: favorites
        .map((f) => SourceInterest(
              sourceId: f.sourceId,
              state: InterestState.favorite,
              priorityMultiplier: 1.0,
            ))
        .toList(),
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 7,
  );
}

/// [score] non nul ⇒ chaque article porte un `recommendationReason` de ce
/// `scoreTotal`. C'est le seul input du tri des blocs (PR-4) : sans lui, aucune
/// section n'entre dans `blockScores` et l'ordre reste celui par défaut.
FeedResponse _feedWithIds(
  List<String> ids, {
  String sourceId = 's',
  double? score,
}) {
  return FeedResponse(
    items: ids
        .map((id) => Content(
              id: id,
              title: 'title-$id',
              url: 'https://x.test/$id',
              contentType: ContentType.article,
              publishedAt: DateTime(2026, 1, 1),
              source: Source(
                id: sourceId,
                name: 'S',
                type: SourceType.article,
              ),
              recommendationReason: score == null
                  ? null
                  : RecommendationReason(
                      label: 'Recommandé',
                      scoreTotal: score,
                    ),
            ))
        .toList(),
    pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
    carousels: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  setUpAll(() {
    // Le FluxContinuNotifier ouvre une box Hive (cache Tournée) au build.
    // `readToday` avale l'erreur, mais une box ouvrable garde le build propre.
    Hive.init(Directory.systemTemp.createTempSync('flux_sources_hive').path);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(() => digestRepo.fetchBothDigests())
        .thenThrow(Exception('mock: no digest'));
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
  });

  /// Un seul stub couvrant tous les named args que le provider peut passer
  /// (thème vs source), avec branchement sur l'invocation.
  void stubFeed({
    required Map<String, List<String>> themeIds,
    required Map<String, List<String>> sourceIds,
    // PR-4 — `score_total` uniforme appliqué aux articles d'un thème/source.
    // Absent ⇒ articles non scorés ⇒ section hors du classement par score.
    Map<String, double> themeScores = const {},
    Map<String, double> sourceScores = const {},
  }) {
    when(() => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          sourceId: any(named: 'sourceId'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        )).thenAnswer((invocation) async {
      final src = invocation.namedArguments[#sourceId] as String?;
      final theme = invocation.namedArguments[#theme] as String?;
      if (src != null) {
        return _feedWithIds(
          sourceIds[src] ?? const [],
          sourceId: src,
          score: sourceScores[src],
        );
      }
      if (theme != null) {
        return _feedWithIds(
          themeIds[theme] ?? const [],
          score: themeScores[theme],
        );
      }
      return _feedWithIds(const []);
    });
  }

  Future<ProviderContainer> buildContainer({
    required UserInterestsState interests,
    required UserSourcesState sourcesState,
    required List<Source> catalog,
    List<String> tourneeOrder = const [],
  }) async {
    // Story 10.2 — une source ne s'affiche dans la Tournée que si sa clé
    // `source:<id>` est en mode « Essentiel » (dans `tournee_order_v1`).
    if (tourneeOrder.isNotEmpty) {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_order_v1': tourneeOrder,
      });
    }
    final container = ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider
            .overrideWithValue(_StubEssentielRepository()),
        userInterestsProvider
            .overrideWith(() => _StubUserInterestsNotifier(interests)),
        userSourcesStateProvider
            .overrideWith(() => _StubUserSourcesStateNotifier(sourcesState)),
        userSourcesProvider
            .overrideWith(() => _StubUserSourcesNotifier(catalog)),
        // Évite la chaîne authStateProvider → Supabase.instance (non initialisé
        // en test). Notifier réel mais sans le `ref.watch(authStateProvider)`.
        sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref, null)),
        // Le cap de fit lit displayModeSpecProvider (box Hive 'settings' non
        // ouverte en test) ⇒ court-circuit.
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
      ],
    );
    // Pré-résout les providers de sources : le FluxContinuNotifier les lit en
    // `ref.read(...).valueOrNull` (synchrone) pendant son build.
    await container.read(userSourcesStateProvider.future);
    await container.read(userSourcesProvider.future);
    await container.read(userInterestsProvider.future);
    return container;
  }

  Source _source(String id, {String? theme, String? logoUrl}) => Source(
        id: id,
        name: 'Source $id',
        type: SourceType.article,
        theme: theme,
        logoUrl: logoUrl,
      );

  List<FeedThemeSection> feedSections(ProviderContainer container) {
    final state = container.read(fluxContinuProvider).requireValue;
    return state.sections.whereType<FeedThemeSection>().toList();
  }

  test(
      'une source favorite produit une section kind=source ordonnée après les '
      'thèmes, avec nom + logo', () async {
    stubFeed(
      themeIds: {
        'tech': ['t1', 't2', 't3']
      },
      sourceIds: {
        'src1': ['a1', 'a2', 'a3']
      },
    );
    final container = await buildContainer(
      interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
      sourcesState: _sourcesState(
        favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
      ),
      catalog: [
        _source('src1', theme: 'society', logoUrl: 'https://logo.test/x.png'),
      ],
      tourneeOrder: const ['theme:tech', 'source:src1'],
    );
    addTearDown(container.dispose);

    await settle(container);
    final sections = feedSections(container);

    final themeIdx = sections.indexWhere((s) => s.kind == SectionKind.theme);
    final sourceIdx = sections.indexWhere((s) => s.kind == SectionKind.source);
    expect(themeIdx, isNonNegative, reason: 'section thème attendue');
    expect(sourceIdx, isNonNegative, reason: 'section source attendue');
    expect(sourceIdx, greaterThan(themeIdx),
        reason: 'la source doit être composée après les thèmes');

    final src = sections[sourceIdx];
    expect(src.sourceId, 'src1');
    expect(src.label, 'Source src1');
    expect(src.sourceLogoUrl, 'https://logo.test/x.png');
    expect(src.items.map((c) => c.id), ['a1', 'a2', 'a3']);
  });

  test(
      'dédup inter-sections : un article partagé thème(au-dessus)/source '
      'n\'apparaît que dans le thème', () async {
    stubFeed(
      themeIds: {
        'tech': ['shared', 't2', 't3']
      },
      // src1 garde 3 survivants uniques (a2/a3/a4) après dédup ⇒ au plancher
      // d'affichage, donc ni backfill (qui repiocherait l'article partagé) ni
      // masquage : on teste ici la seule règle de dédup (le thème au-dessus
      // gagne l'article partagé).
      sourceIds: {
        'src1': ['shared', 'a2', 'a3', 'a4']
      },
    );
    final container = await buildContainer(
      interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
      sourcesState: _sourcesState(
        favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
      ),
      catalog: [_source('src1', theme: 'society')],
      tourneeOrder: const ['theme:tech', 'source:src1'],
    );
    addTearDown(container.dispose);

    await settle(container);
    final sections = feedSections(container);

    final theme = sections.firstWhere((s) => s.kind == SectionKind.theme);
    final source = sections.firstWhere((s) => s.kind == SectionKind.source);
    expect(theme.items.map((c) => c.id), contains('shared'));
    expect(source.items.map((c) => c.id), isNot(contains('shared')),
        reason: 'le thème au-dessus gagne l\'article partagé');
    expect(source.items.map((c) => c.id), ['a2', 'a3', 'a4']);
  });

  test(
      'source sans article frais : section masquée (plancher d\'affichage) '
      'mais signalée à la modal', () async {
    // Renversement assumé de l'ancien contrat « section source toujours
    // visible, même vide » (parité veille) : la règle PO V1 préfère un flux
    // propre à un empty-state, à condition que le masquage soit **dit**
    // (`starvedFavoriteKeys` → badge « Pas assez d'articles » dans « Mes
    // favoris »). Une disparition silencieuse resterait interdite.
    stubFeed(
      themeIds: const {},
      sourceIds: {'src1': const []},
    );
    final container = await buildContainer(
      interests: _interestsState(),
      sourcesState: _sourcesState(
        favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
      ),
      catalog: [_source('src1', theme: 'society')],
      tourneeOrder: const ['theme:tech', 'source:src1'],
    );
    addTearDown(container.dispose);

    final state = await settle(container);
    final source =
        feedSections(container).where((s) => s.kind == SectionKind.source);
    expect(source, isEmpty, reason: 'sous le plancher ⇒ hors du flux');
    expect(state.starvedFavoriteKeys, contains('source:src1'),
        reason: 'masqué n\'est pas silencieux : la modal doit pouvoir le dire');
  });

  test(
      'plusieurs sources favorites respectent l\'ordre par position et le '
      'cap (parité thèmes = 13)', () async {
    stubFeed(
      themeIds: const {},
      sourceIds: {
        'a': ['a1', 'a2', 'a3'],
        'b': ['b1', 'b2', 'b3'],
        'c': ['c1', 'c2', 'c3'],
        'd': ['d1', 'd2', 'd3'],
        'e': ['e1', 'e2', 'e3'],
        'f': ['f1', 'f2', 'f3'],
        'g': ['g1', 'g2', 'g3'],
        'h': ['h1', 'h2', 'h3'],
        'i': ['i1', 'i2', 'i3'],
        'j': ['j1', 'j2', 'j3'],
        'k': ['k1', 'k2', 'k3'],
        'l': ['l1', 'l2', 'l3'],
        'm': ['m1', 'm2', 'm3'],
        'n': ['n1', 'n2', 'n3'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(),
      sourcesState: _sourcesState(favorites: [
        SourceFavoriteRef(sourceId: 'c', position: 2),
        SourceFavoriteRef(sourceId: 'a', position: 0),
        SourceFavoriteRef(sourceId: 'b', position: 1),
        SourceFavoriteRef(sourceId: 'd', position: 3),
        SourceFavoriteRef(sourceId: 'f', position: 5),
        SourceFavoriteRef(sourceId: 'e', position: 4),
        SourceFavoriteRef(sourceId: 'h', position: 7),
        SourceFavoriteRef(sourceId: 'g', position: 6),
        SourceFavoriteRef(sourceId: 'j', position: 9),
        SourceFavoriteRef(sourceId: 'i', position: 8),
        SourceFavoriteRef(sourceId: 'k', position: 10),
        SourceFavoriteRef(sourceId: 'l', position: 11),
        SourceFavoriteRef(sourceId: 'm', position: 12),
        SourceFavoriteRef(sourceId: 'n', position: 13),
      ]),
      catalog: [
        _source('a'),
        _source('b'),
        _source('c'),
        _source('d'),
        _source('e'),
        _source('f'),
        _source('g'),
        _source('h'),
        _source('i'),
        _source('j'),
        _source('k'),
        _source('l'),
        _source('m'),
        _source('n'),
      ],
      tourneeOrder: const [
        'source:a',
        'source:b',
        'source:c',
        'source:d',
        'source:e',
        'source:f',
        'source:g',
        'source:h',
        'source:i',
        'source:j',
        'source:k',
        'source:l',
        'source:m',
        'source:n',
      ],
    );
    addTearDown(container.dispose);

    await settle(container);
    final sources = feedSections(container)
        .where((s) => s.kind == SectionKind.source)
        .map((s) => s.sourceId)
        .toList();

    // Triées par position (a..n) puis capées à 13 → a..m.
    expect(
      sources,
      ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i', 'j', 'k', 'l', 'm'],
    );
  });

  // ── Compromis d'affichage V1 : masquage (pénurie) / déclassement (pauvreté) ─
  group('compromis d\'affichage (masquage / déclassement)', () {
    test(
        'masquage : un bloc résolu sous le plancher sort du flux et part dans '
        'starvedFavoriteKeys', () async {
      stubFeed(
        themeIds: {
          'tech': ['t1', 't2', 't3'] // au plancher → reste
        },
        sourceIds: {
          'src1': ['b1'] // sous le plancher, rien à réinjecter → masqué
        },
      );
      final container = await buildContainer(
        interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
        sourcesState: _sourcesState(
          favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
        ),
        catalog: [_source('src1', theme: 'society')],
        tourneeOrder: const ['theme:tech', 'source:src1'],
      );
      addTearDown(container.dispose);

      final state = await settle(container);
      final kinds = feedSections(container).map((s) => s.kind).toList();
      expect(kinds, contains(SectionKind.theme));
      expect(kinds, isNot(contains(SectionKind.source)));
      expect(state.starvedFavoriteKeys, contains('source:src1'));
      expect(state.starvedFavoriteKeys, isNot(contains('theme:tech')));
    });

    test(
        'backfill : un bloc vidé par la dédup est renfloué jusqu\'au plancher '
        'et RESTE affiché (cas Technologie/Environnement)', () async {
      // Le bug d'origine : les meilleurs articles d'un thème remontent dans le
      // bloc amont, la dédup vide le thème, et il disparaissait. Ici tout est
      // partagé → 0 survivant → le backfill doit le ramener à 3.
      stubFeed(
        themeIds: {
          'tech': ['s1', 's2', 's3'] // gagne les 3 articles
        },
        sourceIds: {
          'src1': ['s1', 's2', 's3'] // tout partagé → 0 survivant
        },
      );
      final container = await buildContainer(
        interests: _interestsState(favorites: [ThemeFavoriteRef(slug: 'tech')]),
        sourcesState: _sourcesState(
          favorites: [SourceFavoriteRef(sourceId: 'src1', position: 0)],
        ),
        catalog: [_source('src1', theme: 'society')],
        tourneeOrder: const ['theme:tech', 'source:src1'],
      );
      addTearDown(container.dispose);

      final state = await settle(container);
      final source = feedSections(container)
          .firstWhere((s) => s.kind == SectionKind.source);
      expect(source.items, hasLength(kSectionMinItems));
      expect(source.items.map((c) => c.id), containsAll(['s1', 's2', 's3']));
      expect(source.underfilled, isTrue);
      expect(state.starvedFavoriteKeys, isEmpty,
          reason: 'renfloué ⇒ affiché ⇒ pas de masquage à expliquer');
    });

    test(
        'déclassement : un bloc pauvre descend sous les autres favoris mais '
        'reste affiché', () async {
      // 5 blocs à 300 (3 × 100) et un à 30 : médiane 300, seuil 150 → seul
      // 'culture' est déclassé. Il descend en fin de bloc favori, il ne
      // disparaît pas.
      stubFeed(
        themeIds: {
          'tech': ['tc1', 'tc2', 'tc3'],
          'science': ['sc1', 'sc2', 'sc3'],
          'culture': ['cu1', 'cu2', 'cu3'],
          'economy': ['ec1', 'ec2', 'ec3'],
          'politics': ['po1', 'po2', 'po3'],
          'environment': ['en1', 'en2', 'en3'],
        },
        sourceIds: const {},
        themeScores: const {
          'tech': 100,
          'science': 100,
          'culture': 10, // 30 < 150 ⇒ pauvre
          'economy': 100,
          'politics': 100,
          'environment': 100,
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
            ThemeFavoriteRef(slug: 'environment'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      final state = await settle(container);
      final order = feedSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      expect(order, hasLength(6), reason: 'un bloc pauvre reste affiché');
      expect(order.last, 'culture');
      expect(state.starvedFavoriteKeys, isEmpty);
    });

    test('déclassement inactif quand tous les blocs se valent', () async {
      // Médiane 300, seuil 150, tout le monde à 300 : personne n'est en retrait
      // → l'ordre composé par l'utilisateur est rendu tel quel.
      stubFeed(
        themeIds: {
          'tech': ['tc1', 'tc2', 'tc3'],
          'science': ['sc1', 'sc2', 'sc3'],
          'culture': ['cu1', 'cu2', 'cu3'],
        },
        sourceIds: const {},
        themeScores: const {'tech': 100, 'science': 100, 'culture': 100},
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'culture'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await settle(container);
      final order = feedSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      expect(order, ['tech', 'science', 'culture']);
    });

    test(
        'déclassement inactif sous kPoorDemotionMinBlocks blocs scorés '
        '(médiane non significative)', () async {
      stubFeed(
        themeIds: {
          'tech': ['tc1', 'tc2', 'tc3'],
          'culture': ['cu1', 'cu2', 'cu3'],
        },
        sourceIds: const {},
        themeScores: const {'tech': 100, 'culture': 1},
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'culture'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await settle(container);
      final order = feedSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      // 2 blocs scorés < 3 ⇒ aucun déclassement : 'culture' garde son rang.
      expect(order, ['tech', 'culture']);
    });

    test('aucun article scoré ⇒ ordre inchangé (sentinelle)', () async {
      // Sans `recommendationReason`, aucune section n'entre dans `blockScores` :
      // ni tri ni déclassement, chaque bloc garde sa position absolue. C'est le
      // filet qui protège les blocs non scorés (éditoriaux, veille sans
      // scoring) de couler à 0.
      stubFeed(
        themeIds: {
          'tech': ['tc1', 'tc2', 'tc3'],
          'science': ['sc1', 'sc2', 'sc3'],
          'culture': ['cu1', 'cu2', 'cu3'],
          'economy': ['ec1', 'ec2', 'ec3'],
          'politics': ['po1', 'po2', 'po3'],
        },
        sourceIds: const {},
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await settle(container);
      final order = feedSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      expect(order, ['tech', 'science', 'culture', 'economy', 'politics']);
    });
  });
}
