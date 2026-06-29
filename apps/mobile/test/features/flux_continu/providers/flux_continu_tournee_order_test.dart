// PR 2 — couverture du bloc favori UNIFIÉ de la Tournée composé par le
// FluxContinuNotifier : ordre 100 % libre (thèmes + sources + veille mélangés
// via « Composer ma Tournée »), cap d'affichage 13, exclusion des sujets perso,
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
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
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

import 'flux_continu_settle.dart';

class _MockDigestRepository extends Mock implements DigestRepository {}

class _MockFeedRepository extends Mock implements FeedRepository {}

class _MockFluxContinuRepository extends Mock
    implements FluxContinuRepository {}

class _StubEssentielRepository implements EssentielRepository {
  @override
  Future<List<EssentielArticle>?> fetch({bool? serein, DateTime? date}) async => const [];
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
    favoriteCap: 7,
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
    favoriteCap: 7,
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

// 2 topics : « Actus du jour » (kind=essentiel) doit franchir le plancher
// `_kActusMinTopics` du provider, sinon la section est masquée et l'ordre
// favoris → Actus → Bonnes ne peut pas être vérifié.
DigestResponse _digest(String id) => DigestResponse(
      digestId: id,
      userId: 'u',
      targetDate: DateTime(2026, 1, 1),
      generatedAt: DateTime(2026, 1, 1),
      topics: [_digestTopic('$id-a'), _digestTopic('$id-b')],
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
        // Le cap de fit lit displayModeSpecProvider (box Hive 'settings' non
        // ouverte en test) ⇒ court-circuit.
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
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
      'ordre normal par défaut : favoris puis Actus (+ Grille slot) puis Bonnes',
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

        final state = await settle(container);

        // Ordre par défaut demandé : favoris utilisateur, puis Actus du jour,
        // puis Bonnes Nouvelles.
        expect(state.sections.map(sectionKey).toList(), [
          'theme:society',
          kTourneeActusKey,
          kTourneeBonnesKey,
        ]);
        expect(
          state.grilleSlotIndex,
          2,
          reason: 'La Grille est rendue juste après Actus (ici en 2e position)',
        );
      },
    );

    test('cap 13 : 8 thèmes + Actus + Grille + Bonnes tiennent (rien coupé)',
        () async {
      stubDigest();
      stubFeed(
        themeIds: {
          'society': ['s1'],
          'culture': ['c1'],
          'economy': ['e1'],
          'politics': ['p1'],
          'tech': ['t1'],
          'science': ['sc1'],
          'environment': ['en1'],
          'international': ['in1'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'society'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'environment'),
            ThemeFavoriteRef(slug: 'international'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
        grilleToday: _grilleToday(),
      );
      addTearDown(container.dispose);

      final state = await settle(container);

      // 8 thèmes + Actus + Grille + Bonnes = 11 items ≤ cap 13 → tout tient.
      expect(state.sections.map(sectionKey).toList(), [
        'theme:society',
        'theme:culture',
        'theme:economy',
        'theme:politics',
        'theme:tech',
        'theme:science',
        'theme:environment',
        'theme:international',
        kTourneeActusKey,
        kTourneeBonnesKey,
      ]);
      expect(state.grilleSlotIndex, 9);
      expect(
        state.sections.map(sectionKey),
        contains(kTourneeBonnesKey),
        reason: '8 thèmes + Actus + Grille + Bonnes = 11 items tiennent sous le '
            'cap de 13 (Bonnes n\'est plus coupée)',
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

      final state = await settle(container);

      expect(state.sections.map(sectionKey), [kTourneeBonnesKey]);
      expect(state.grilleSlotIndex, isNull);
    });

    test(
      'mode serène par défaut : même ordre que normal (favoris, Actus, Bonnes)',
      () async {
        // Plan QA onboarding — le mode serein garde l'ordre par défaut demandé
        // (favoris → Actus → Bonnes), avec les contenus serein. Plus de Bonnes
        // remontées en tête.
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

        final state = await settle(container);

        expect(state.sections.map(sectionKey).toList(), [
          'theme:society',
          kTourneeActusKey,
          kTourneeBonnesKey,
        ]);
        expect(state.grilleSlotIndex, 2);
      },
    );

    test(
      'mode serène customisé sans ordre : garde le défaut unifié',
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

        final state = await settle(container);

        expect(state.sections.map(sectionKey).toList(), [
          'theme:society',
          kTourneeActusKey,
          kTourneeBonnesKey,
        ]);
        expect(state.grilleSlotIndex, 2);
      },
    );

    test('ordre utilisateur prime en mode serène (Grille épinglée après Actus)',
        () async {
      // La clé `grille` héritée d'un ordre legacy est ignorée pour le
      // positionnement : la Grille n'est plus réordonnable et reste collée aux
      // Actus. Le reste de l'ordre utilisateur (actus/bonnes) prime.
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

      final state = await settle(container);

      expect(state.sections.map(sectionKey).toList(), [
        kTourneeActusKey,
        kTourneeBonnesKey,
        'theme:society',
      ]);
      // Grille juste après les Actus (index 1), pas après les Bonnes.
      expect(state.grilleSlotIndex, 1);
    });
  });

  test(
      'cap d\'affichage 13 : 7 thèmes + 6 sources + veille (14 candidats) → '
      'seulement 13 sections, veille (en queue par défaut) coupée', () async {
    // Story 10.2 — les sources doivent être en mode « Essentiel » (clé dans
    // l'ordre) pour entrer dans la Tournée ; on garde l'ordre par défaut
    // (thèmes avant sources) en plaçant les clés thème d'abord.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_order_v1': [
        'theme:society',
        'theme:culture',
        'theme:economy',
        'theme:politics',
        'theme:tech',
        'theme:science',
        'theme:environment',
        'source:a',
        'source:b',
        'source:c',
        'source:d',
        'source:e',
        'source:f',
      ],
    });
    stubFeed(
      themeIds: {
        'society': ['s1', 's2'],
        'culture': ['c1', 'c2'],
        'economy': ['e1', 'e2'],
        'politics': ['p1', 'p2'],
        'tech': ['t1', 't2'],
        'science': ['sc1', 'sc2'],
        'environment': ['en1', 'en2'],
      },
      sourceIds: {
        'a': ['a1'],
        'b': ['b1'],
        'c': ['c9'],
        'd': ['d1'],
        'e': ['e9'],
        'f': ['f1'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(
        favorites: const [
          ThemeFavoriteRef(slug: 'society'),
          ThemeFavoriteRef(slug: 'culture'),
          ThemeFavoriteRef(slug: 'economy'),
          ThemeFavoriteRef(slug: 'politics'),
          ThemeFavoriteRef(slug: 'tech'),
          ThemeFavoriteRef(slug: 'science'),
          ThemeFavoriteRef(slug: 'environment'),
        ],
      ),
      sourcesState: _sourcesState(
        favorites: const [
          SourceFavoriteRef(sourceId: 'a', position: 0),
          SourceFavoriteRef(sourceId: 'b', position: 1),
          SourceFavoriteRef(sourceId: 'c', position: 2),
          SourceFavoriteRef(sourceId: 'd', position: 3),
          SourceFavoriteRef(sourceId: 'e', position: 4),
          SourceFavoriteRef(sourceId: 'f', position: 5),
        ],
      ),
      catalog: [
        source('a'),
        source('b'),
        source('c'),
        source('d'),
        source('e'),
        source('f'),
      ],
      veilleCfg: _veilleCfg(),
    );
    addTearDown(container.dispose);

    await settle(container);
    final sections = favoriteSections(container);

    expect(
      sections,
      hasLength(13),
      reason: 'cap d\'affichage de la Tournée = 13',
    );
    expect(
      sections.where((s) => s.kind == SectionKind.veille),
      isEmpty,
      reason: 'ordre par défaut thèmes→sources→veille → veille en 14e, coupée',
    );
    // Ordre par défaut : 7 thèmes puis 6 sources (a..f) ; veille tombe.
    expect(sections.map((s) => s.kind).toList(), [
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.theme,
      SectionKind.source,
      SectionKind.source,
      SectionKind.source,
      SectionKind.source,
      SectionKind.source,
      SectionKind.source,
    ]);
    expect(
      sections
          .where((s) => s.kind == SectionKind.source)
          .map((s) => s.sourceId),
      ['a', 'b', 'c', 'd', 'e', 'f'],
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

    await settle(container);
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
      // remontée en tête. 14 candidats → cap 13, veille première (source f tombe).
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_order_v1': [
          'veille',
          'theme:society',
          'theme:culture',
          'theme:economy',
          'theme:politics',
          'theme:tech',
          'theme:science',
          'theme:environment',
          'source:a',
          'source:b',
          'source:c',
          'source:d',
          'source:e',
          'source:f',
        ],
      });
      stubFeed(
        themeIds: {
          'society': ['s1', 's2'],
          'culture': ['c1', 'c2'],
          'economy': ['e1', 'e2'],
          'politics': ['p1', 'p2'],
          'tech': ['t1', 't2'],
          'science': ['sc1', 'sc2'],
          'environment': ['en1', 'en2'],
        },
        sourceIds: {
          'a': ['a1'],
          'b': ['b1'],
          'c': ['c9'],
          'd': ['d1'],
          'e': ['e9'],
          'f': ['f1'],
        },
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'society'),
            ThemeFavoriteRef(slug: 'culture'),
            ThemeFavoriteRef(slug: 'economy'),
            ThemeFavoriteRef(slug: 'politics'),
            ThemeFavoriteRef(slug: 'tech'),
            ThemeFavoriteRef(slug: 'science'),
            ThemeFavoriteRef(slug: 'environment'),
          ],
        ),
        sourcesState: _sourcesState(
          favorites: const [
            SourceFavoriteRef(sourceId: 'a', position: 0),
            SourceFavoriteRef(sourceId: 'b', position: 1),
            SourceFavoriteRef(sourceId: 'c', position: 2),
            SourceFavoriteRef(sourceId: 'd', position: 3),
            SourceFavoriteRef(sourceId: 'e', position: 4),
            SourceFavoriteRef(sourceId: 'f', position: 5),
          ],
        ),
        catalog: [
          source('a'),
          source('b'),
          source('c'),
          source('d'),
          source('e'),
          source('f'),
        ],
        veilleCfg: _veilleCfg(),
      );
      addTearDown(container.dispose);

      await settle(container);
      final sections = favoriteSections(container);

      expect(sections, hasLength(13));
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

      await settle(container);
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

      await settle(container);
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
        // Story 22.3 — le triplet canonique codé en dur a été retiré : un
        // compte neuf sans top-themes ne voit plus tech/environment/science
        // injectés (le padding vient des suggestions « Choisie pour vous »).
        '0 favori + customized=false + 0 source/veille + top-themes vide ⇒ '
        'pas de fallback canonique', () async {
      stubFeed();
      final container = await buildContainer(
        interests: _interestsState(),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await settle(container);
      final slugs = favoriteSections(container)
          .where((s) => s.kind == SectionKind.theme)
          .map((s) => s.themeSlug)
          .toList();
      expect(
        slugs,
        isEmpty,
        reason: 'plus de triplet canonique codé en dur (Story 22.3)',
      );
    });

    test(
        // Story 22.3 — un compte neuf est désormais complété par les sections
        // suggérées (origin=suggested) servies par le backend, badgées.
        '0 favori + suggestions backend ⇒ sections « Choisie pour vous »',
        () async {
      when(() => fluxRepo.getTopThemes()).thenAnswer(
        (_) async => const [
          TopTheme(
            interestSlug: 'tech',
            weight: 1.0,
            articleCount: 4,
            origin: 'suggested',
            reason: SuggestionReason(label: 'Tu suis ce thème'),
          ),
        ],
      );
      stubFeed(themeIds: {'tech': ['a', 'b']});
      final container = await buildContainer(
        interests: _interestsState(),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);

      await settle(container);
      final suggested = favoriteSections(container)
          .where((s) => s.isSuggested)
          .toList();
      expect(suggested, hasLength(1));
      expect(suggested.first.themeSlug, 'tech');
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

      await settle(container);
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

      await settle(container);
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

    await settle(container);
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

    final state = await settle(container);

    expect(
      state.sections.map(sectionKey),
      isNot(contains('theme:society')),
      reason: 'thème en mode Flâner absent des sections Essentiel',
    );
  });

  test(
      'hotfix Grille — compte personnalisé sans clé grille dans order : la '
      'Grille reste épinglée juste après les Actus (pas coupée par le cap)',
      () async {
    // Régression : la Grille n'étant plus réordonnable, sa clé `grille` est
    // absente de `tournee_order_v1`. `applyOrder` la reléguait en fin de liste
    // → coupée par le cap → disparition totale. Elle doit rester collée
    // aux Actus.
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_customized_v1': true,
      'tournee_order_v1': [
        'essentiel',
        'theme:society',
        'theme:culture',
        'theme:economy',
        'theme:tech',
      ],
    });
    stubDigest();
    stubFeed(
      themeIds: {
        'society': ['s1'],
        'culture': ['c1'],
        'economy': ['e1'],
        'tech': ['t1'],
      },
    );
    final container = await buildContainer(
      interests: _interestsState(
        favorites: const [
          ThemeFavoriteRef(slug: 'society'),
          ThemeFavoriteRef(slug: 'culture'),
          ThemeFavoriteRef(slug: 'economy'),
          ThemeFavoriteRef(slug: 'tech'),
        ],
      ),
      sourcesState: _sourcesState(),
      catalog: const [],
      grilleToday: _grilleToday(),
    );
    addTearDown(container.dispose);

    final state = await settle(container);

    expect(
      state.grilleSlotIndex,
      1,
      reason: 'La Grille est rendue juste après les Actus, malgré l\'absence '
          'de sa clé dans l\'ordre personnalisé',
    );
    expect(sectionKey(state.sections.first), kTourneeActusKey);
  });
}
