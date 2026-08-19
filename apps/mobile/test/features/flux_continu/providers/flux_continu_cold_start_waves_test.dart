// Tests du réordonnancement du cold boot « héros d'abord » (lot
// cold-start-load-order, B1/B2/B3) :
//
//  - vague 1 : `/api/essentiel` est dispatché STRICTEMENT avant digest/both et
//    top-thèmes, et aucun provider annexe (grille, alertes, thèmes suivis)
//    n'est initialisé pendant cette fenêtre ;
//  - vague 2 : gatée sur min(essentiel résolu, 600 ms) — un essentiel pendu ne
//    retarde jamais le digest de plus de la tête d'avance ;
//  - vague 3 : les providers annexes ne s'initialisent qu'après la Phase 1 ;
//  - B3 : le fan-out part dans l'ordre de RENDU (ordre custom sticky compris),
//    et les suggestions hors du cap affiché ne sont pas fetchées (+1 réserve).
import 'dart:async';
import 'dart:io';

import 'package:facteur/features/alerts/providers/alerts_provider.dart';
import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/flux_continu/services/flux_continu_cache_service.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
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

/// Stub essentiel pilotable : chaque `fetch()` notifie [onFetch] puis renvoie
/// [result] (une future fournie par le test — complétable à la demande).
class _GatedEssentielRepository implements EssentielRepository {
  _GatedEssentielRepository({
    required this.result,
    this.onFetch,
  });

  final Future<EssentielFetchResult?> Function() result;
  final void Function()? onFetch;

  @override
  Future<EssentielFetchResult?> fetch({bool? serein, DateTime? date}) {
    onFetch?.call();
    return result();
  }

  @override
  Future<List<Map<String, dynamic>>?> fetchMore({
    required List<String> excludeIds,
    int limit = 2,
  }) async =>
      const [];

  @override
  Future<bool> postTriage({
    required String digestDate,
    required int slateSize,
    required List<Map<String, dynamic>> decisions,
  }) async =>
      true;
}

class _NoGrilleRepository implements GrilleRepository {
  @override
  Future<GrilleTodayResponse> getToday() async =>
      throw Exception('mock: no grille');

  @override
  Future<GrilleLeaderboardResponse> getLeaderboard() =>
      throw UnimplementedError();

  @override
  Future<GrilleRevealResponse> revealWord() => throw UnimplementedError();

  @override
  Future<GrilleGuessResponse> submitGuess(String mot) =>
      throw UnimplementedError();
}

class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._initial);

  final UserInterestsState _initial;

  @override
  Future<UserInterestsState> build() async => _initial;
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

EssentielFetchResult _essentielResult({int articles = 0}) => (
      articles: [
        for (var i = 0; i < articles; i++)
          EssentielArticle(
            contentId: 'ess-$i',
            title: 'Essentiel $i',
            url: 'https://x.test/ess/$i',
            publishedAt: DateTime(2026, 1, 1),
            sourceName: 'S',
            sourceLetter: 'S',
            sectionLabel: 'Essentiel',
            rank: i + 1,
          ),
      ],
      newSinceMorning: 0,
      carousel: null,
    );

FeedResponse _feedResponseWith(int items, {String prefix = 'c'}) {
  return FeedResponse(
    items: List.generate(
      items,
      (i) => Content(
        id: '$prefix-$i',
        title: 't$i',
        url: 'https://x.test/$prefix/$i',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 1, 1),
        source: Source(id: 's', name: 'S', type: SourceType.article),
      ),
    ),
    pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
    carousels: const [],
  );
}

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

  ProviderContainer makeContainer({
    required EssentielRepository essentielRepo,
    UserInterestsState? interests,
  }) {
    return ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider.overrideWithValue(essentielRepo),
        grilleRepositoryProvider.overrideWithValue(_NoGrilleRepository()),
        userInterestsProvider.overrideWith(
          () => _StubUserInterestsNotifier(interests ?? _interestsState()),
        ),
        sereinToggleProvider
            .overrideWith((ref) => SereinToggleNotifier(ref, null)),
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
      ],
    );
  }

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('flux_waves_hive').path);
  });

  setUp(() async {
    await clearFluxCache();
    SharedPreferences.setMockInitialValues(<String, Object>{});
    digestRepo = _MockDigestRepository();
    feedRepo = _MockFeedRepository();
    fluxRepo = _MockFluxContinuRepository();

    when(() => digestRepo.fetchBothDigests())
        .thenThrow(Exception('mock: no digest'));
    when(() => fluxRepo.getTopThemes())
        .thenAnswer((_) async => const <TopTheme>[]);
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
    ).thenAnswer((_) async => _feedResponseWith(3));
  });

  tearDown(() async {
    await pumpEventQueue(times: 5);
    await clearFluxCache();
  });

  test(
    'vague 1 — essentiel dispatché STRICTEMENT avant digest et top-thèmes',
    () async {
      final calls = <String>[];
      when(() => digestRepo.fetchBothDigests()).thenAnswer((_) {
        calls.add('digest');
        throw Exception('mock: no digest');
      });
      when(() => fluxRepo.getTopThemes()).thenAnswer((_) async {
        calls.add('topThemes');
        return const <TopTheme>[];
      });

      final container = makeContainer(
        essentielRepo: _GatedEssentielRepository(
          onFetch: () => calls.add('essentiel'),
          result: () async => _essentielResult(articles: 5),
        ),
        interests: _interestsState(
          favorites: const [ThemeFavoriteRef(slug: 'tech')],
        ),
      );
      addTearDown(container.dispose);

      await settle(container);

      expect(calls, isNotEmpty);
      expect(calls.first, 'essentiel',
          reason: 'le paquet prioritaire part seul, en premier');
      expect(calls, containsAll(['digest', 'topThemes']));
    },
  );

  test(
    'vagues 1→3 — aucun provider annexe initialisé tant que l\'essentiel est '
    'en vol ; tous armés après la Phase 1',
    () async {
      final gate = Completer<EssentielFetchResult?>();
      final container = makeContainer(
        essentielRepo: _GatedEssentielRepository(result: () => gate.future),
      );
      addTearDown(container.dispose);

      container.read(fluxContinuProvider);
      await pumpEventQueue(times: 20);

      // Vague 1 en vol (essentiel pendu, temps réel < 600 ms) : rien d'annexe
      // ne doit être vivant — ni via ref.listen (déférés en vague 3), ni via
      // les lectures furtives de la composition squelette (_peekValue).
      expect(container.exists(alertsProvider), isFalse,
          reason: 'alertes = vague 3, jamais pendant la vague 1');
      expect(container.exists(grilleProvider), isFalse,
          reason: 'grille = vague 3, jamais pendant la vague 1');
      expect(container.exists(themesFollowedProvider), isFalse,
          reason: 'thèmes suivis = vague 3, jamais pendant la vague 1');

      gate.complete(_essentielResult(articles: 5));
      await settle(container);

      // Vague 3 armée : les listeners différés ont initialisé leurs providers.
      expect(container.exists(alertsProvider), isTrue);
      expect(container.exists(grilleProvider), isTrue);
      expect(container.exists(themesFollowedProvider), isTrue);
    },
  );

  test(
    'vague 2 — essentiel pendu : digest part à ~600 ms (tête d\'avance '
    'bornée), jamais immédiatement',
    () async {
      final never = Completer<EssentielFetchResult?>();
      final sw = Stopwatch()..start();
      var digestCalledAtMs = -1;
      when(() => digestRepo.fetchBothDigests()).thenAnswer((_) {
        digestCalledAtMs = sw.elapsedMilliseconds;
        throw Exception('mock: no digest');
      });

      final container = makeContainer(
        essentielRepo: _GatedEssentielRepository(result: () => never.future),
      );
      addTearDown(container.dispose);

      container.read(fluxContinuProvider);
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await pumpEventQueue(times: 3);
      // Sous forte charge machine ce point de contrôle peut être atteint après
      // la tête d'avance — on ne l'asserte que si on est encore dedans.
      if (sw.elapsedMilliseconds < 500) {
        expect(digestCalledAtMs, -1,
            reason: 'digest ne part pas avant la tête d\'avance du héros');
      }

      // Attend la borne (600 ms) avec de la marge.
      while (digestCalledAtMs < 0 && sw.elapsedMilliseconds < 3000) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await pumpEventQueue(times: 3);
      }
      expect(digestCalledAtMs, greaterThanOrEqualTo(550),
          reason: 'la vague 2 attend min(essentiel, 600 ms)');
      expect(digestCalledAtMs, lessThan(3000),
          reason: 'un essentiel pendu ne bloque pas la vague 2 (gate borné)');

      // Résout l'essentiel pour laisser le build se terminer proprement.
      never.complete(_essentielResult());
      await settle(container);
    },
  );

  test(
    'B3 — le fan-out part dans l\'ordre de RENDU (ordre custom sticky), pas '
    'l\'ordre des favoris',
    () async {
      // Ordre custom inversé : la Tournée affiche theme2 → theme1 → theme0.
      SharedPreferences.setMockInitialValues(<String, Object>{
        'tournee_order_v1': <String>[
          'theme:theme2',
          'theme:theme1',
          'theme:theme0',
        ],
        'tournee_customized_v1': true,
      });

      final fetchedThemes = <String>[];
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
        final theme = invocation.namedArguments[#theme] as String?;
        if (theme != null) fetchedThemes.add(theme);
        return _feedResponseWith(3, prefix: theme ?? 'x');
      });

      final container = makeContainer(
        essentielRepo: _GatedEssentielRepository(
          result: () async => _essentielResult(articles: 5),
        ),
        interests: _interestsState(
          favorites: const [
            ThemeFavoriteRef(slug: 'theme0'),
            ThemeFavoriteRef(slug: 'theme1'),
            ThemeFavoriteRef(slug: 'theme2'),
          ],
        ),
      );
      addTearDown(container.dispose);

      await settle(container);

      expect(fetchedThemes, ['theme2', 'theme1', 'theme0'],
          reason: 'les fetchs suivent l\'ordre d\'affichage custom, plus '
              'l\'ordre de déclaration des favoris');
    },
  );

  test(
    'B3 — les suggestions hors du cap affiché ne sont pas fetchées '
    '(+1 de réserve pour dismissSuggestion)',
    () async {
      // 10 favoris + 9 suggestions. Cap d'affichage 16 (Story 22.8), 10 favoris
      // occupent 10 slots → 6 suggestions visibles ; fetchées = 6 + 1 réserve
      // = 7 ; les 2 dernières ne sont jamais fetchées.
      final favorites = <FavoriteRef>[
        for (var i = 0; i < 10; i++) ThemeFavoriteRef(slug: 'theme$i'),
      ];
      when(() => fluxRepo.getTopThemes()).thenAnswer(
        (_) async => [
          for (var i = 0; i < 9; i++)
            TopTheme(
              interestSlug: 'sugg$i',
              weight: 1,
              origin: 'suggested',
              dailyRank: 100 + i,
            ),
        ],
      );

      final fetchedThemes = <String>[];
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
        final theme = invocation.namedArguments[#theme] as String?;
        if (theme != null) fetchedThemes.add(theme);
        return _feedResponseWith(3, prefix: theme ?? 'x');
      });

      final container = makeContainer(
        essentielRepo: _GatedEssentielRepository(
          result: () async => _essentielResult(articles: 5),
        ),
        interests: _interestsState(favorites: favorites),
      );
      addTearDown(container.dispose);

      await settle(container);

      // Tous les favoris fetchés (aucune perte de couverture).
      for (var i = 0; i < 10; i++) {
        expect(fetchedThemes, contains('theme$i'));
      }
      // Suggestions : les 6 visibles sous le cap + 1 réserve, dans l'ordre
      // daily_rank — les 2 dernières ne sont jamais fetchées.
      final suggFetched =
          fetchedThemes.where((t) => t.startsWith('sugg')).toList();
      expect(
          suggFetched,
          ['sugg0', 'sugg1', 'sugg2', 'sugg3', 'sugg4', 'sugg5', 'sugg6'],
          reason: 'suggestions visibles (6) + 1 réserve, jamais le reste');
    },
  );
}
