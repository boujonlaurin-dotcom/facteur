// Bug « Sources favorites absentes » — les 2 races du bootstrap de la Tournée.
//
//  - Race 1 : la réconciliation du placement (DB → prefs) se résout PENDANT le
//    bootstrap, fenêtre où les listeners de prefs sont muets ⇒ l'hydratation qui
//    restaure l'appartenance Essentiel d'une source était avalée (section absente
//    jusqu'au prochain cold boot). Cf. `_reconcilePlacementThenSync`.
//  - Race 2 : le catalogue `userSourcesProvider` est lazy ⇒ un favori source non
//    encore résolu était silencieusement droppé du seed ET du fan-out pour tout
//    le cycle. Cf. `_ensureSourceCatalog`.
import 'dart:async';
import 'dart:io';

import 'package:facteur/features/digest/providers/digest_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/digest/repositories/digest_repository.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/tournee_order_prefs_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
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

/// Catalogue de sources résolu par un [Completer] : permet de simuler un
/// catalogue qui n'arrive qu'APRÈS le démarrage du bootstrap (race 2).
class _DeferredUserSourcesNotifier extends UserSourcesNotifier {
  _DeferredUserSourcesNotifier(this._future);
  final Future<List<Source>> _future;
  @override
  Future<List<Source>> build() => _future;
}

Source _source(String id) =>
    Source(id: id, name: 'Source $id', type: SourceType.article);

UserInterestsState _emptyInterests() => const UserInterestsState(
      themes: [],
      customTopics: [],
      favorites: [],
      favoriteCount: 0,
      favoriteCap: 7,
    );

/// État sources backend : un favori `src1`, dont le placement DB est [essentiel]
/// (null = jamais placé).
UserSourcesState _sourcesState({bool? essentiel}) => UserSourcesState(
      sources: [
        SourceInterest(
          sourceId: 'src1',
          state: InterestState.favorite,
          priorityMultiplier: 1.0,
          essentielMode: essentiel,
        ),
      ],
      favorites: const [SourceFavoriteRef(sourceId: 'src1', position: 0)],
      favoriteCount: 1,
      favoriteCap: 7,
    );

FeedResponse _feedWithIds(List<String> ids, {String sourceId = 'src1'}) =>
    FeedResponse(
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
              ))
          .toList(),
      pagination: Pagination(page: 1, perPage: 10, total: 0, hasNext: false),
      carousels: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockDigestRepository digestRepo;
  late _MockFeedRepository feedRepo;
  late _MockFluxContinuRepository fluxRepo;

  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('flux_races_hive').path);
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
      return _feedWithIds(src == null ? const [] : const ['a1', 'a2']);
    });
  });

  ProviderContainer buildContainer({
    required UserSourcesState sourcesState,
    required Future<List<Source>> catalog,
  }) {
    return ProviderContainer(
      overrides: [
        digestRepositoryProvider.overrideWithValue(digestRepo),
        feedRepositoryProvider.overrideWithValue(feedRepo),
        fluxContinuRepositoryProvider.overrideWithValue(fluxRepo),
        essentielRepositoryProvider
            .overrideWithValue(_StubEssentielRepository()),
        userInterestsProvider
            .overrideWith(() => _StubUserInterestsNotifier(_emptyInterests())),
        userSourcesStateProvider
            .overrideWith(() => _StubUserSourcesStateNotifier(sourcesState)),
        userSourcesProvider
            .overrideWith(() => _DeferredUserSourcesNotifier(catalog)),
        sereinToggleProvider
            .overrideWith((ref) => SereinToggleNotifier(ref, null)),
        displayModeSpecProvider.overrideWithValue(DisplayModeSpec.normal),
      ],
    );
  }

  List<FeedThemeSection> sourceSections(ProviderContainer container) => container
      .read(fluxContinuProvider)
      .requireValue
      .sections
      .whereType<FeedThemeSection>()
      .where((s) => s.kind == SectionKind.source)
      .toList();

  test(
      'race 1 — le placement Essentiel restauré par la réconciliation pendant '
      'le bootstrap fait apparaître la section sans cold boot', () async {
    // Device fraîchement réinstallé : `tournee_order_v1` vide (le placement
    // local est perdu), mais la DB sait que src1 est en mode Essentiel.
    final container = buildContainer(
      sourcesState: _sourcesState(essentiel: true),
      catalog: Future.value([_source('src1')]),
    );
    addTearDown(container.dispose);
    expect(container.read(tourneeOrderPrefsProvider).essentielSourceKeys,
        isEmpty);

    await settle(container);

    expect(sourceSections(container).map((s) => s.sourceId), ['src1'],
        reason: 'la section source doit apparaître dans le cycle courant');
    expect(container.read(tourneeOrderPrefsProvider).essentielSourceKeys,
        contains('source:src1'),
        reason: 'l\'hydratation DB → prefs a bien eu lieu');
  });

  test(
      'race 2 — un catalogue de sources résolu tardivement ne fait pas '
      'disparaître la section', () async {
    SharedPreferences.setMockInitialValues(<String, Object>{
      'tournee_order_v1': <String>['source:src1'],
    });
    final catalog = Completer<List<Source>>();
    final container = buildContainer(
      // Placement déjà connu côté DB ⇒ la réconciliation est un no-op : seule
      // la résolution tardive du catalogue est en jeu ici.
      sourcesState: _sourcesState(essentiel: true),
      catalog: catalog.future,
    );
    addTearDown(container.dispose);

    // Démarre le bootstrap catalogue NON résolu, puis le résout en cours de route.
    container.read(fluxContinuProvider);
    await pumpEventQueue(times: 5);
    catalog.complete([_source('src1')]);

    await settle(container);

    expect(sourceSections(container).map((s) => s.sourceId), ['src1'],
        reason: 'le favori ne doit pas être droppé pour tout le cycle');
    expect(sourceSections(container).single.items.map((c) => c.id),
        ['a1', 'a2']);
  });
}
