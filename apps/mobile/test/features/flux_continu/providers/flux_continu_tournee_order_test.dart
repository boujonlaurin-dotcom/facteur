// PR 2 — couverture du bloc favori UNIFIÉ de la Tournée composé par le
// FluxContinuNotifier : ordre 100 % libre (thèmes + sources + veille mélangés
// via « Composer ma Tournée »), cap d'affichage [kTourneeVisibleCap], exclusion
// des sujets perso, et masquage de la veille (veilleHidden).
import 'dart:io';

import 'package:facteur/config/constants.dart' show kFavoriteCap;
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/models/dual_digest_response.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/providers/tab_order_prefs_provider.dart';
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

import 'feed_repository_mock.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'flux_continu_settle.dart';

class _MockDigestRepository extends Mock implements DigestRepository {}

// Le fan-out appelle getFeedWithRaw (SWR in-day) : le mock partagé délègue
// vers getFeed, que ces suites stubbent.
typedef _MockFeedRepository = MockFeedRepository;

typedef _MockFluxContinuRepository = MockFluxContinuRepository;

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

/// Complète une liste **non vide** jusqu'au plancher d'affichage
/// [kSectionMinItems], avec des ids dérivés et donc uniques.
///
/// Ce fichier teste l'**ordre** des blocs, pas le compromis d'affichage V1
/// (masquage/déclassement, couvert par `flux_continu_sources_test.dart`). Sans
/// ce padding, chaque fixture à 1-2 articles serait masquée et masquerait du
/// même coup ce que le test veut vérifier. Une liste vide le reste : les tests
/// de pénurie/empty-state gardent tout leur sens.
List<String> _atLeastFloor(List<String> ids) => ids.isEmpty
    ? ids
    : [
        ...ids,
        for (var i = ids.length; i < kSectionMinItems; i++) '${ids.first}_pad$i',
      ];

FeedResponse _feedWithIds(
  List<String> rawIds, {
  String sourceId = 's',
  bool pad = true,
}) {
  final ids = pad ? _atLeastFloor(rawIds) : rawIds;
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
    // `false` ⇒ fixtures servies telles quelles : réservé aux tests qui portent
    // sur le plancher d'affichage lui-même (cf. [_atLeastFloor]).
    bool pad = true,
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
        return _feedWithIds(
          sourceIds[src] ?? const [],
          sourceId: src,
          pad: pad,
        );
      }
      if (theme != null) {
        return _feedWithIds(themeIds[theme] ?? const [], pad: pad);
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
        sereinToggleProvider.overrideWith((ref) => SereinToggleNotifier(ref, null)),
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

  /// Sections « Choisie pour vous » renvoyées par `getTopThemes`.
  List<TopTheme> suggestedThemes(List<String> slugs) => [
        for (final slug in slugs)
          TopTheme(
            interestSlug: slug,
            weight: 1.0,
            articleCount: 4,
            origin: 'suggested',
            reason: const SuggestionReason(label: 'Tu suis ce thème'),
          ),
      ];

  /// Feed thème minimal (2 articles) pour chaque slug — de quoi construire une
  /// section non maigre.
  Map<String, List<String>> themeFeedFor(List<String> slugs) => {
        for (final slug in slugs) slug: ['$slug-1', '$slug-2'],
      };

  group('invariants de dimensionnement du cap (Story 22.8)', () {
    test('kTourneeEditorialCount reste égal au nombre de clés éditoriales', () {
      // `kTourneeEditorialCount` est un `const int` écrit à la main parce que
      // `kTourneeVisibleCap` en dérive et que Dart ne const-fold pas
      // `List.length`. Ce test est le seul lien entre les deux : ajouter une
      // carte éditoriale sans incrémenter le compteur rétrécirait le cap d'un
      // slot et couperait une section en silence.
      expect(kTourneeEditorialCount, kTourneeEditorialKeys.length);
      expect(
        kTourneeEditorialKeys,
        containsAll([kTourneeActusKey, kTourneeGrilleKey, kTourneeBonnesKey]),
      );
    });

    test('le cap laisse la place à l\'éditorial + un plafond de favoris', () {
      // Inégalité que la valeur de `kTourneeVisibleCap` encode. Le test
      // « plafond de favoris + suggestions » plus bas la vérifie de bout en
      // bout ; celui-ci l'énonce sur les constantes seules, donc il localise la
      // panne sur la bonne ligne si quelqu'un dé-dérive le cap. La marge de
      // suggestions (kTourneeSuggestQuota) est en plus : hors marge, le cap doit
      // encore couvrir favoris + éditorial.
      expect(
        kTourneeVisibleCap - kTourneeSuggestQuota,
        greaterThanOrEqualTo(kTourneeEditorialCount + kFavoriteCap),
      );
    });
  });

  group('éditorial + Grille dans la liste unifiée', () {
    test(
      'ordre normal par défaut (compte non personnalisé) : Actus en tête '
      '(+ Grille slot) puis favoris puis Bonnes',
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

        // Ordre par défaut pour tous les nouveaux utilisateurs : Actus du jour
        // en première section, puis favoris, puis Bonnes Nouvelles.
        expect(state.sections.map(sectionKey).toList(), [
          kTourneeActusKey,
          'theme:society',
          kTourneeBonnesKey,
        ]);
        expect(
          state.grilleSlotIndex,
          1,
          reason: 'La Grille est rendue juste après Actus (ici en 2e position)',
        );
      },
    );

    test('sous le cap : 8 thèmes + Actus + Grille + Bonnes tiennent '
        '(rien coupé)', () async {
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

      // Actus en tête (compte non personnalisé), puis 8 thèmes, puis Bonnes.
      // + Grille = 11 items ≤ cap → tout tient. Le cas *au plafond* de favoris
      // (le seul où le cap mord sur l'éditorial) est couvert par le test
      // « plafond de favoris + suggestions » juste en dessous.
      expect(state.sections.map(sectionKey).toList(), [
        kTourneeActusKey,
        'theme:society',
        'theme:culture',
        'theme:economy',
        'theme:politics',
        'theme:tech',
        'theme:science',
        'theme:environment',
        'theme:international',
        kTourneeBonnesKey,
      ]);
      expect(state.grilleSlotIndex, 1);
      expect(
        state.sections.map(sectionKey),
        contains(kTourneeBonnesKey),
        reason: '8 thèmes + Actus + Grille + Bonnes = 11 items tiennent sous le '
            'cap (Bonnes n\'est plus coupée)',
      );
    });

    test(
        'plafond de favoris + suggestions : Actus + Grille + Bonnes survivent '
        'au cap plein (Story 22.8)', () async {
      // Exécute en vrai l'inégalité que [kTourneeVisibleCap] encode :
      // `cap - kTourneeSuggestQuota >= kTourneeEditorialCount + kFavoriteCap`.
      // Bonnes Nouvelles est la dernière du bloc éditorial, donc la première
      // sacrifiée si le cap est sous-dimensionné — la panne est silencieuse.
      // Depuis #1098 les suggestions ne mordent plus : à plafond de favoris
      // plein (kFavoriteCap) + éditorial, la marge de suggestions se remplit sur
      // les slots restants sans jamais évincer un favori ni une carte.
      final favSlugs = [for (var i = 0; i < kFavoriteCap; i++) 'theme$i'];
      // Assez de suggestions pour occuper la marge du cap (kTourneeSuggestQuota).
      final sugSlugs = [
        for (var i = 0; i < kTourneeSuggestQuota; i++) 'sug$i',
      ];
      stubDigest();
      when(() => fluxRepo.getTopThemes())
          .thenAnswer((_) async => suggestedThemes(sugSlugs));
      stubFeed(themeIds: themeFeedFor([...favSlugs, ...sugSlugs]));
      final container = await buildContainer(
        interests: _interestsState(
          favorites: [for (final s in favSlugs) ThemeFavoriteRef(slug: s)],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
        grilleToday: _grilleToday(),
      );
      addTearDown(container.dispose);

      final state = await settle(container);
      final keys = state.sections.map(sectionKey).toList();

      expect(
        keys,
        contains(kTourneeBonnesKey),
        reason: 'Bonnes Nouvelles tombe la première si '
            '`kTourneeVisibleCap - kTourneeSuggestQuota` est trop petit pour '
            '`kTourneeEditorialCount + kFavoriteCap`',
      );
      expect(keys, contains(kTourneeActusKey));
      expect(state.grilleSlotIndex, isNotNull);
      // Les favoris ne sont pas sacrifiés non plus : le plafond entier tient.
      expect(
        keys.where((k) => k.startsWith('theme:theme')).length,
        kFavoriteCap,
        reason: 'aucun favori sous le plafond ne doit être coupé',
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
      'mode serène par défaut : même ordre que normal (Actus, favoris, Bonnes)',
      () async {
        // Plan QA onboarding — le mode serein garde l'ordre par défaut demandé
        // (Actus → favoris → Bonnes), avec les contenus serein. Plus de Bonnes
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
          kTourneeActusKey,
          'theme:society',
          kTourneeBonnesKey,
        ]);
        expect(state.grilleSlotIndex, 1);
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
      'cap d\'affichage : 7 thèmes + 9 sources + veille (17 candidats) → '
      'seulement `kTourneeVisibleCap` sections, veille (en queue par défaut) '
      'coupée', () async {
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
        'source:g',
        'source:h',
        'source:i',
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
        'g': ['g1'],
        'h': ['h1'],
        'i': ['i1'],
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
          SourceFavoriteRef(sourceId: 'g', position: 6),
          SourceFavoriteRef(sourceId: 'h', position: 7),
          SourceFavoriteRef(sourceId: 'i', position: 8),
        ],
      ),
      catalog: [
        source('a'),
        source('b'),
        source('c'),
        source('d'),
        source('e'),
        source('f'),
        source('g'),
        source('h'),
        source('i'),
      ],
      veilleCfg: _veilleCfg(),
    );
    addTearDown(container.dispose);

    await settle(container);
    final sections = favoriteSections(container);

    expect(
      sections,
      hasLength(kTourneeVisibleCap),
      reason: 'cap d\'affichage de la Tournée',
    );
    expect(
      sections.where((s) => s.kind == SectionKind.veille),
      isEmpty,
      reason: 'ordre par défaut thèmes→sources→veille → veille en dernier, '
          'donc coupée par le cap',
    );
    // Ordre par défaut : 7 thèmes puis 9 sources (a..i) ; veille tombe.
    expect(sections.map((s) => s.kind).toList(), [
      for (var i = 0; i < 7; i++) SectionKind.theme,
      for (var i = 0; i < kTourneeVisibleCap - 7; i++) SectionKind.source,
    ]);
    expect(
      sections
          .where((s) => s.kind == SectionKind.source)
          .map((s) => s.sourceId),
      ['a', 'b', 'c', 'd', 'e', 'f', 'g', 'h', 'i'],
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
      // remontée en tête. 17 candidats → cap `kTourneeVisibleCap` (16), veille
      // première, la dernière source tombe.
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
          'source:g',
          'source:h',
          'source:i',
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
          'g': ['g1'],
          'h': ['h1'],
          'i': ['i1'],
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
            SourceFavoriteRef(sourceId: 'g', position: 6),
            SourceFavoriteRef(sourceId: 'h', position: 7),
            SourceFavoriteRef(sourceId: 'i', position: 8),
          ],
        ),
        catalog: [
          source('a'),
          source('b'),
          source('c'),
          source('d'),
          source('e'),
          source('f'),
          source('g'),
          source('h'),
          source('i'),
        ],
        veilleCfg: _veilleCfg(),
      );
      addTearDown(container.dispose);

      await settle(container);
      final sections = favoriteSections(container);

      expect(sections, hasLength(kTourneeVisibleCap));
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

  group('suggestions sous le cap : les favoris ne cèdent jamais un slot', () {
    // Exactement `kTourneeVisibleCap` slugs thématiques favoris = cap plein,
    // sans marge pour les suggestions (bug « blocs favoris absents » : depuis
    // #1098 les suggestions ne réservent plus rien, elles prennent les slots
    // restants). Générés depuis la constante (et non listés en dur) pour que le
    // groupe garde sa prémisse à chaque bump du cap.
    final favSlugs = [for (var i = 0; i < kTourneeVisibleCap; i++) 'fav$i'];

    Future<ProviderContainer> personalized({
      required List<String> suggestedSlugs,
      required List<String> hiddenKeys,
    }) async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_customized_v1': true,
        'tournee_order_v1': [for (final s in favSlugs) 'theme:$s'],
        if (hiddenKeys.isNotEmpty) 'tournee_hidden_keys_v1': hiddenKeys,
      });
      when(() => fluxRepo.getTopThemes())
          .thenAnswer((_) async => suggestedThemes(suggestedSlugs));
      stubFeed(themeIds: themeFeedFor([...favSlugs, ...suggestedSlugs]));
      final container = await buildContainer(
        interests: _interestsState(
          favorites: [for (final s in favSlugs) ThemeFavoriteRef(slug: s)],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);
      await settle(container);
      return container;
    }

    test(
        'cap plein de favoris : aucun favori évincé, les suggestions cèdent '
        'tous les slots', () async {
      // Bug « blocs favoris absents de l'Essentiel » : avant, le quota 22.6
      // réservait 3 slots aux suggestions en coupant 3 favoris (`cap - quota`).
      // Un bloc placé par l'utilisateur ne disparaît plus jamais au profit
      // d'une « Choisie pour vous ».
      final container = await personalized(
        suggestedSlugs: const ['sugA', 'sugB', 'sugC', 'sugD'],
        hiddenKeys: const [],
      );
      final sections = favoriteSections(container);
      expect(sections, hasLength(kTourneeVisibleCap));
      expect(sections.where((s) => s.isSuggested), isEmpty);
      expect(
        sections.map((s) => s.themeSlug).toList(),
        favSlugs,
        reason: 'les blocs choisis tiennent le cap, dans l\'ordre manuel',
      );
    });

    test('un favori masqué rend son slot à une suggestion', () async {
      // 1 favori dismissé ⇒ 1 slot libre ⇒ la meilleure suggestion le prend.
      // Les suggestions vivent sur les restes, jamais aux dépens d'un favori.
      final container = await personalized(
        suggestedSlugs: const ['sugA', 'sugB', 'sugC'],
        hiddenKeys: const ['theme:fav0'],
      );
      final sections = favoriteSections(container);
      expect(sections, hasLength(kTourneeVisibleCap));
      final suggestedVisible = sections.where((s) => s.isSuggested).toList();
      expect(suggestedVisible.map((s) => s.themeSlug).toList(), ['sugA']);
      final favVisible = sections.where((s) => !s.isSuggested).toList();
      expect(
        favVisible.map((s) => s.themeSlug).toList(),
        favSlugs.where((s) => s != 'fav0'),
      );
    });

    test('non-personnalisé sous le cap ⇒ ordre naturel inchangé', () async {
      // 2 favoris + 2 suggestions tiennent largement sous le cap : pas de
      // rééquilibrage, suggestions à leur position naturelle (après favoris).
      when(() => fluxRepo.getTopThemes())
          .thenAnswer((_) async => suggestedThemes(const ['sugA', 'sugB']));
      stubFeed(
        themeIds: themeFeedFor(
          const ['society', 'culture', 'sugA', 'sugB'],
        ),
      );
      final container = await buildContainer(
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'society'),
            ThemeFavoriteRef(slug: 'culture'),
          ],
        ),
        sourcesState: _sourcesState(),
        catalog: const [],
      );
      addTearDown(container.dispose);
      await settle(container);

      final sections = favoriteSections(container);
      expect(
        sections.map((s) => s.themeSlug).toList(),
        ['society', 'culture', 'sugA', 'sugB'],
        reason: 'favoris puis suggestions best-first, aucun rééquilibrage',
      );
      expect(
        sections.where((s) => s.isSuggested).map((s) => s.themeSlug).toList(),
        ['sugA', 'sugB'],
      );
    });
  });

  test(
      'thème favori explicite à 1 item ⇒ masqué pour la journée, et dit comme '
      'tel (compromis d\'affichage V1)', () async {
    // Historiquement ce thème restait rendu à 1 article (« jamais coupé »), au
    // prix d'un bloc quasi vide. La règle PO V1 tranche l'inverse : sous le
    // plancher d'affichage il sort du flux — à la condition stricte que
    // l'utilisateur puisse l'apprendre (`starvedFavoriteKeys` → badge « Pas
    // assez d'articles » dans « Mes favoris »). Ce qui reste interdit, c'est la
    // disparition *silencieuse*.
    stubFeed(
      themeIds: {
        'society': ['only-one'],
      },
      pad: false,
    );
    final container = await buildContainer(
      interests: _interestsState(
        favorites: const [ThemeFavoriteRef(slug: 'society')],
      ),
      sourcesState: _sourcesState(),
      catalog: const [],
    );
    addTearDown(container.dispose);

    final state = await settle(container);
    final society = favoriteSections(
      container,
    ).where((s) => s.themeSlug == 'society');
    expect(society, isEmpty, reason: 'sous le plancher ⇒ hors du flux');
    expect(
      state.starvedFavoriteKeys,
      contains('theme:society'),
      reason: 'masqué, mais jamais en silence',
    );
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
