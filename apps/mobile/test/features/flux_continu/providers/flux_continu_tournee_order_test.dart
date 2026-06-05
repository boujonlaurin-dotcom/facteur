// PR 2 — couverture du bloc favori UNIFIÉ de la Tournée composé par le
// FluxContinuNotifier : ordre 100 % libre (thèmes + sources + veille mélangés
// via « Composer ma Tournée »), cap d'affichage 5, exclusion des sujets perso,
// et masquage de la veille (veilleHidden).
import 'dart:io';

import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/models/dual_digest_response.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/providers/tab_order_prefs_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/flux_continu/services/flux_continu_cache_service.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_active_config_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockDigestRepository extends Mock implements DigestRepository {}

class _MockFeedRepository extends Mock implements FeedRepository {}

class _MockFluxContinuRepository extends Mock
    implements FluxContinuRepository {}

class _StubEssentielRepository implements EssentielRepository {
  @override
  Future<List<EssentielArticle>?> fetch() async => const [];
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

class _StubVeilleActiveConfigNotifier extends VeilleActiveConfigNotifier {
  _StubVeilleActiveConfigNotifier(this._cfg);
  final VeilleConfigDto? _cfg;
  @override
  Future<VeilleConfigDto?> build() async => _cfg;
}

class _FakeGrilleRepository implements GrilleRepository {
  _FakeGrilleRepository(this.today);

  final GrilleTodayResponse? today;

  @override
  Future<GrilleTodayResponse> getToday() async {
    final value = today;
    if (value == null) throw Exception('mock: no grille');
    return value;
  }

  @override
  Future<GrilleRevealResponse> revealWord() => throw UnimplementedError();

  @override
  Future<GrilleGuessResponse> submitGuess(String mot) =>
      throw UnimplementedError();

  @override
  Future<GrilleLeaderboardResponse> getLeaderboard() =>
      throw UnimplementedError();
}

UserInterestsState _interestsState({List<FavoriteRef> favorites = const []}) {
  return UserInterestsState(
    themes: const [],
    customTopics: const [],
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 5,
  );
}

UserSourcesState _sourcesState({List<SourceFavoriteRef> favorites = const []}) {
  return UserSourcesState(
    sources: favorites
        .map(
          (f) => SourceInterest(
            sourceId: f.sourceId,
            state: InterestState.favorite,
            priorityMultiplier: 1.0,
          ),
        )
        .toList(),
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 5,
  );
}

VeilleConfigDto _veilleCfg({String id = 'cfg1'}) => VeilleConfigDto(
      id: id,
      userId: 'u',
      themeId: 'tech',
      themeLabel: 'Tech',
      status: 'active',
      createdAt: DateTime(2026, 1, 1),
      updatedAt: DateTime(2026, 1, 1),
      topics: const [],
      sources: const [],
      keywords: const [],
    );

FeedResponse _feedWithIds(List<String> ids, {String sourceId = 's'}) {
  return FeedResponse(
    items: ids
        .map(
          (id) => Content(
            id: id,
            title: 'title-$id',
            url: 'https://x.test/$id',
            contentType: ContentType.article,
            publishedAt: DateTime(2026, 1, 1),
            source: Source(id: sourceId, name: 'S', type: SourceType.article),
          ),
        )
        .toList(),
    pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
    carousels: const [],
  );
}

GrilleTodayResponse _grilleToday() => const GrilleTodayResponse(
      date: '2026-05-30',
      dateAffichee: 'Vendredi 30 mai',
      dateCourt: 'Ven. 30 mai',
      numero: 'N°143',
      longueur: 6,
      essaisMax: 6,
      premiereLettre: 'C',
      indice: 'indice',
      theme: 'theme',
      statut: 'in_progress',
      essais: [],
      nbEssais: 0,
      streak: 5,
      prochainMotDansSec: 1000,
    );

DigestItem _digestItem(String id) => DigestItem(
      contentId: id,
      title: 'digest-$id',
      url: 'https://x.test/digest/$id',
      source: const SourceMini(name: 'Digest Source'),
      publishedAt: DateTime(2026, 1, 1),
    );

DigestTopic _digestTopic(String id) => DigestTopic(
      topicId: id,
      label: 'Topic $id',
      articles: [_digestItem('digest-$id')],
    );

DigestResponse _digest(String id) => DigestResponse(
      digestId: id,
      userId: 'u',
      targetDate: DateTime(2026, 1, 1),
      generatedAt: DateTime(2026, 1, 1),
      topics: [_digestTopic(id)],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  Future<void> clearFluxCache() async {
    final cacheBox = Hive.isBoxOpen(FluxContinuCacheService.boxName)
        ? Hive.box<String>(FluxContinuCacheService.boxName)
        : await Hive.openBox<String>(FluxContinuCacheService.boxName);
    await cacheBox.clear();
  }

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('flux_tournee_hive').path);
  });

  setUp(() async {
    await clearFluxCache();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(
      () => digestRepo.fetchBothDigests(),
    ).thenThrow(Exception('mock: no digest'));
    when(
      () => fluxRepo.getTopThemes(),
    ).thenAnswer((_) async => const <TopTheme>[]);
    // Veille feed — always-visible section, contenu indifférent ici.
    when(
      () => fluxRepo.getVeilleFeedItems(
        limit: any(named: 'limit'),
        serein: any(named: 'serein'),
      ),
    ).thenAnswer((_) async => _feedWithIds(const ['v1', 'v2']));
  });

  tearDown(() async {
    await pumpEventQueue(times: 5);
    await clearFluxCache();
  });

  void stubFeed({
    Map<String, List<String>> themeIds = const {},
    Map<String, List<String>> sourceIds = const {},
  }) {
    when(
      () => feedRepo.getFeed(
        page: any(named: 'page'),
        limit: any(named: 'limit'),
        theme: any(named: 'theme'),
        topic: any(named: 'topic'),
        sourceId: any(named: 'sourceId'),
        serein: any(named: 'serein'),
        personalized: any(named: 'personalized'),
      ),
    ).thenAnswer((invocation) async {
      final src = invocation.namedArguments[#sourceId] as String?;
      final theme = invocation.namedArguments[#theme] as String?;
      if (src != null) {
        return _feedWithIds(sourceIds[src] ?? const [], sourceId: src);
      }
      if (theme != null) {
        return _feedWithIds(themeIds[theme] ?? const []);
      }
      return _feedWithIds(const []);
    });
  }

  Future<ProviderContainer> buildContainer({
    required UserInterestsState interests,
    required UserSourcesState sourcesState,
    required List<Source> catalog,
    VeilleConfigDto? veilleCfg,
    GrilleTodayResponse? grilleToday,
    bool isSerene = false,
  }) async {
    final container = ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider.overrideWithValue(
          _StubEssentielRepository(),
        ),
        grilleRepositoryProvider.overrideWithValue(
          _FakeGrilleRepository(grilleToday),
        ),
        userInterestsProvider.overrideWith(
          () => _StubUserInterestsNotifier(interests),
        ),
        userSourcesStateProvider.overrideWith(
          () => _StubUserSourcesStateNotifier(sourcesState),
        ),
        userSourcesProvider.overrideWith(
          () => _StubUserSourcesNotifier(catalog),
        ),
        veilleActiveConfigProvider.overrideWith(
          () => _StubVeilleActiveConfigNotifier(veilleCfg),
        ),
        sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref)),
      ],
    );
    container.read(sereinToggleProvider.notifier).setEnabledLocal(isSerene);
    // Pré-résout les providers lus en `valueOrNull` (synchrone) par le notifier.
    await container.read(userSourcesStateProvider.future);
    await container.read(userSourcesProvider.future);
    await container.read(userInterestsProvider.future);
    await container.read(veilleActiveConfigProvider.future);
    try {
      await container.read(grilleProvider.future);
    } catch (_) {
      // No daily word in this scenario.
    }
    // L'ordre Tournée se charge async depuis SharedPreferences dans le ctor du
    // StateNotifier : on l'instancie puis on draine la queue pour que le `build`
    // du FluxContinuNotifier lise l'ordre seedé (et pas l'état vide initial).
    container.read(tourneeOrderPrefsProvider);
    await pumpEventQueue();
    return container;
  }

  Source source(String id, {String? theme, String? logoUrl}) => Source(
        id: id,
        name: 'Source $id',
        type: SourceType.article,
        theme: theme,
        logoUrl: logoUrl,
      );

  List<FeedThemeSection> favoriteSections(ProviderContainer container) {
    final state = container.read(fluxContinuProvider).requireValue;
    return state.sections.whereType<FeedThemeSection>().toList();
  }

  void stubDigest() {
    when(() => digestRepo.fetchBothDigests()).thenAnswer(
      (_) async => DualDigestResponse(
        normal: _digest('normal'),
        serein: _digest('serein'),
        sereinEnabled: false,
      ),
    );
  }

  group('éditorial + Grille dans la liste unifiée', () {
    test(
      'ordre normal par défaut : Actus puis Grille slot puis favoris puis Bonnes',
      () async {
        stubDigest();
        stubFeed(
          themeIds: {
            'society': ['t1'],
          },
        );
        final container = await buildContainer(
          interests: _interestsState(
            favorites: const [ThemeFavoriteRef(slug: 'society')],
          ),
          sourcesState: _sourcesState(),
          catalog: const [],
          grilleToday: _grilleToday(),
        );
        addTearDown(container.dispose);

        final state = await container.read(fluxContinuProvider.future);

        expect(state.sections.map(sectionKey).toList(), [
          kTourneeActusKey,
          'theme:society',
          kTourneeBonnesKey,
        ]);
        expect(
          state.grilleSlotIndex,
          1,
          reason: 'La Grille est rendue juste après Actus en ordre normal',
        );
      },
    );

    test('cap 5 unifié : Actus + Grille + 3 thèmes coupent Bonnes', () async {
      stubDigest();
      stubFeed(
        themeIds: {
          'society': ['s1'],
          'culture': ['c1'],
          'economy': ['e1'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'society'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
        grilleToday: _grilleToday(),
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      expect(state.sections.map(sectionKey).toList(), [
        kTourneeActusKey,
        'theme:society',
        'theme:culture',
        'theme:economy',
      ]);
      expect(state.grilleSlotIndex, 1);
      expect(
        state.sections.map(sectionKey),
        isNot(contains(kTourneeBonnesKey)),
        reason: 'Bonnes est 6e dans la liste unifiée et tombe sous le cap',
      );
    });

    test('hiddenKeys masque Actus et Grille', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_hidden_keys_v1': [kTourneeActusKey, kTourneeGrilleKey],
      });
      stubDigest();
      stubFeed();
      final container = await buildContainer(
        interests: _interestsState(),
        sourcesState: _sourcesState(),
        catalog: const [],
        grilleToday: _grilleToday(),
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      expect(state.sections.map(sectionKey), [kTourneeBonnesKey]);
      expect(state.grilleSlotIndex, isNull);
    });

    test(
      'mode serène par défaut : Bonnes en premier, Grille après Actus',
      () async {
        stubDigest();
        stubFeed(
          themeIds: {
            'society': ['t1'],
          },
        );
        final container = await buildContainer(
          interests: _interestsState(
            favorites: const [ThemeFavoriteRef(slug: 'society')],
          ),
          sourcesState: _sourcesState(),
          catalog: const [],
          grilleToday: _grilleToday(),
          isSerene: true,
        );
        addTearDown(container.dispose);

        final state = await container.read(fluxContinuProvider.future);

        expect(state.sections.map(sectionKey).toList(), [
          kTourneeBonnesKey,
          'theme:society',
          kTourneeActusKey,
        ]);
        expect(state.grilleSlotIndex, 3);
      },
    );

    test(
      'mode serène customisé sans ordre : garde le défaut normal',
      () async {
        SharedPreferences.setMockInitialValues(<String, Object>{
          'tournee_customized_v1': true,
        });
        stubDigest();
        stubFeed(
          themeIds: {
            'society': ['t1'],
          },
        );
        final container = await buildContainer(
          interests: _interestsState(
            favorites: const [ThemeFavoriteRef(slug: 'society')],
          ),
          sourcesState: _sourcesState(),
          catalog: const [],
          grilleToday: _grilleToday(),
          isSerene: true,
        );
        addTearDown(container.dispose);

        final state = await container.read(fluxContinuProvider.future);

        expect(state.sections.map(sectionKey).toList(), [
          kTourneeActusKey,
          'theme:society',
          kTourneeBonnesKey,
        ]);
        expect(state.grilleSlotIndex, 1);
      },
    );

    test('ordre utilisateur prime en mode serène', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_order_v1': [
          kTourneeActusKey,
          kTourneeBonnesKey,
          kTourneeGrilleKey,
        ],
      });
      stubDigest();
      stubFeed(
        themeIds: {
          'society': ['t1'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [ThemeFavoriteRef(slug: 'society')],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
        grilleToday: _grilleToday(),
        isSerene: true,
      );
      addTearDown(container.dispose);

      final state = await container.read(fluxContinuProvider.future);

      expect(state.sections.map(sectionKey).toList(), [
        kTourneeActusKey,
        kTourneeBonnesKey,
        'theme:society',
      ]);
      expect(state.grilleSlotIndex, 2);
    });
  });

  test(
      'cap d\'affichage 5 : 3 thèmes + 3 sources + veille (7 candidats) → '
      'seulement 5 sections, veille (en queue par défaut) coupée', () async {
    // Story 10.2 — les sources doivent être en mode « Essentiel » (clé dans
    // l'ordre) pour entrer dans la Tournée ; on garde l'ordre par défaut
    // (thèmes avant sources) en plaçant les clés thème d'abord.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_order_v1': [
        'theme:society',
        'theme:culture',
        'theme:economy',
        'source:a',
        'source:b',
        'source:c',
      ],
    });
    stubFeed(
      themeIds: {
        'society': ['s1', 's2'],
        'culture': ['c1', 'c2'],
        'economy': ['e1', 'e2'],
      },
      sourceIds: {
        'a': ['a1'],
        'b': ['b1'],
        'c': ['c9'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(
        favorites: const [
          ThemeFavoriteRef(slug: 'society'),
          ThemeFavoriteRef(slug: 'culture'),
          ThemeFavoriteRef(slug: 'economy'),
        ],
      ),
      sourcesState: _sourcesState(
        favorites: const [
          SourceFavoriteRef(sourceId: 'a', position: 0),
          SourceFavoriteRef(sourceId: 'b', position: 1),
          SourceFavoriteRef(sourceId: 'c', position: 2),
        ],
      ),
      catalog: [source('a'), source('b'), source('c')],
      veilleCfg: _veilleCfg(),
    );
    addTearDown(container.dispose);

    await container.read(fluxContinuProvider.future);
    final sections = favoriteSections(container);

    expect(
      sections,
      hasLength(5),
      reason: 'cap d\'affichage de la Tournée = 5',
    );
    expect(
      sections.where((s) => s.kind == SectionKind.veille),
      isEmpty,
      reason: 'ordre par défaut thèmes→sources→veille → veille en 7e, coupée',
    );
    // Ordre par défaut : 3 thèmes puis 2 sources (a, b) ; c et veille tombent.
    expect(sections.map((s) => s.kind).toList(), [
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.source,
      SectionKind.source,
    ]);
    expect(
      sections
          .where((s) => s.kind == SectionKind.source)
          .map((s) => s.sourceId),
      ['a', 'b'],
    );
  });

  test('ordre explicite réordonne le bloc (source avant thème)', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_order_v1': ['source:s1', 'theme:society'],
    });
    stubFeed(
      themeIds: {
        'society': ['t1', 't2'],
      },
      sourceIds: {
        's1': ['x1', 'x2'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(
        favorites: const [ThemeFavoriteRef(slug: 'society')],
      ),
      sourcesState: _sourcesState(
        favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
      ),
      catalog: [source('s1')],
    );
    addTearDown(container.dispose);

    await container.read(fluxContinuProvider.future);
    final sections = favoriteSections(container);

    final sourceIdx = sections.indexWhere((s) => s.kind == SectionKind.source);
    final themeIdx = sections.indexWhere((s) => s.kind == SectionKind.theme);
    expect(sourceIdx, isNonNegative);
    expect(themeIdx, isNonNegative);
    expect(
      sourceIdx,
      lessThan(themeIdx),
      reason: 'l\'ordre prefs place la source avant le thème',
    );
  });

  test(
    'veille en tête d\'ordre : présente dans le cap, un autre item tombe',
    () async {
      // Story 10.2 — sources en mode « Essentiel » (clés dans l'ordre) ; veille
      // remontée en tête. 7 candidats → cap 5, veille première.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_order_v1': [
          'veille',
          'theme:society',
          'theme:culture',
          'theme:economy',
          'source:a',
          'source:b',
          'source:c',
        ],
      });
      stubFeed(
        themeIds: {
          'society': ['s1', 's2'],
          'culture': ['c1', 'c2'],
          'economy': ['e1', 'e2'],
        },
        sourceIds: {
          'a': ['a1'],
          'b': ['b1'],
          'c': ['c9'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'society'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
          ],
        ),
        sourcesState: _sourcesState(
          favorites: const [
            SourceFavoriteRef(sourceId: 'a', position: 0),
            SourceFavoriteRef(sourceId: 'b', position: 1),
            SourceFavoriteRef(sourceId: 'c', position: 2),
          ],
        ),
        catalog: [source('a'), source('b'), source('c')],
        veilleCfg: _veilleCfg(),
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final sections = favoriteSections(container);

      expect(sections, hasLength(5));
      expect(
        sections.first.kind,
        SectionKind.veille,
        reason: 'veille remontée en tête par l\'ordre prefs',
      );
    },
  );

  test(
    'sujet personnalisé favori : exclu de la Tournée (Flâner-only)',
    () async {
      stubFeed(
        themeIds: {
          'society': ['t1', 't2'],
        },
        // Un feed existe pour le sujet perso : il ne doit JAMAIS être fetché ni
        // composé puisque les custom topics sont exclus avant la résolution.
        sourceIds: const {},
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'society'),
            CustomTopicFavoriteRef(id: 'ct1'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final sections = favoriteSections(container);

      expect(
        sections.where((s) => s.kind == SectionKind.theme),
        hasLength(1),
        reason: 'seul le thème society survit',
      );
      expect(
        sections.where((s) => s.customTopicId != null),
        isEmpty,
        reason: 'aucune section issue d\'un sujet perso',
      );
    },
  );

  test(
    'veilleHidden : pas de section veille même avec config active',
    () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_veille_hidden_v1': true,
      });
      stubFeed(
        themeIds: {
          'society': ['t1', 't2'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [ThemeFavoriteRef(slug: 'society')],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
        veilleCfg: _veilleCfg(),
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final sections = favoriteSections(container);

      expect(
        sections.where((s) => s.kind == SectionKind.veille),
        isEmpty,
        reason: 'veille masquée par veilleHidden',
      );
      expect(sections.where((s) => s.kind == SectionKind.theme), hasLength(1));
    },
  );

  group('fallback canonique gaté (Tournée bugs E2E)', () {
    test(
        '0 favori + customized=false + 0 source/veille ⇒ fallback canonique '
        '(compte neuf)', () async {
      // Prefs vides (setUp) → customized=false → compte réellement neuf.
      stubFeed(
        themeIds: {
          'tech': ['a', 'b'],
          'environment': ['a', 'b'],
          'science': ['a', 'b'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final slugs = favoriteSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      expect(
        slugs,
        containsAll(['tech', 'environment', 'science']),
        reason: 'un compte neuf garde sa Tournée par défaut',
      );
    });

    test(
        '0 favori + customized=true ⇒ pas de fallback canonique (retrait '
        'volontaire respecté)', () async {
      // L'utilisateur a vidé sa Tournée puis rechargé : le flag persistant
      // désactive la ré-injection des thèmes canoniques.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_customized_v1': true,
      });
      stubFeed();
      final container = await buildContainer(
        interests: _interestsState(),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      expect(
        favoriteSections(container).where((s) => s.kind == SectionKind.theme),
        isEmpty,
        reason: 'fallback désactivé après personnalisation',
      );
      // Aucun thème canonique n'est même fetché.
      verifyNever(
        () => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          theme: any(named: 'theme'),
          topic: any(named: 'topic'),
          sourceId: any(named: 'sourceId'),
          serein: any(named: 'serein'),
          personalized: any(named: 'personalized'),
        ),
      );
    });

    test(
        '0 favori + customized=false MAIS source favorite ⇒ pas de fallback '
        '(Tournée source-only)', () async {
      // Une source favorite suffit à rendre la Tournée non vide → on ne pad
      // pas avec des thèmes canoniques que l'utilisateur n'a pas choisis.
      // Story 10.2 — source en mode « Essentiel » pour qu'elle rende sa section.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_order_v1': ['source:s1'],
      });
      stubFeed(
        sourceIds: {
          's1': ['x1'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(),
        sourcesState: _sourcesState(
          favorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
        ),
        catalog: [source('s1')],
      );
      addTearDown(container.dispose);

      await container.read(fluxContinuProvider.future);
      final sections = favoriteSections(container);
      expect(
        sections.where((s) => s.kind == SectionKind.theme),
        isEmpty,
        reason: 'présence d\'une source favorite désactive le fallback',
      );
      expect(sections.where((s) => s.kind == SectionKind.source), hasLength(1));
    });
  });

  test(
      'thème favori explicite à 1 item ⇒ section construite (jamais masquée, '
      'miroir source/veille)', () async {
    // Avant le fix, `_buildThemeSection` coupait toute section < 2 items —
    // une section thème favorite « sparse » disparaissait sans feedback.
    stubFeed(
      themeIds: {
        'society': ['only-one'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(
        favorites: const [ThemeFavoriteRef(slug: 'society')],
      ),
      sourcesState: _sourcesState(),
      catalog: const [],
    );
    addTearDown(container.dispose);

    await container.read(fluxContinuProvider.future);
    final society = favoriteSections(
      container,
    ).where((s) => s.themeSlug == 'society').toList();
    expect(
      society,
      hasLength(1),
      reason: 'favori explicite jamais coupé même sous 2 items',
    );
    expect(society.single.items, hasLength(1));
  });

  test(
      'thème livré en Flâner (clé theme: dans pinned_tabs_order) est exclu des '
      'sections Essentiel', () async {
    // Le thème `society` est favori MAIS sa clé `theme:society` est dans
    // l'ordre Flâner ⇒ modèle exclusif ⇒ il vit en onglet, pas dans l'Essentiel.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'pinned_tabs_order_v1': ['theme:society'],
    });
    stubDigest();
    stubFeed(
      themeIds: {
        'society': ['t1'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(
        favorites: const [ThemeFavoriteRef(slug: 'society')],
      ),
      sourcesState: _sourcesState(),
      catalog: const [],
    );
    addTearDown(container.dispose);

    // S'assure que `tabOrderPrefsProvider` a chargé l'ordre seedé avant le
    // `build` du FluxContinuNotifier (cf. tourneeOrderPrefsProvider).
    container.read(tabOrderPrefsProvider);
    await pumpEventQueue();

    final state = await container.read(fluxContinuProvider.future);

    expect(
      state.sections.map(sectionKey),
      isNot(contains('theme:society')),
      reason: 'thème en mode Flâner absent des sections Essentiel',
    );
  });
}
