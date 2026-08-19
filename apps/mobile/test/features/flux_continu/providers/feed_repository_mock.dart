import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:mocktail/mocktail.dart';

/// Mock de [FeedRepository] pour les suites Tournée.
///
/// Depuis le SWR in-day, le fan-out appelle `getFeedWithRaw` (le payload brut
/// alimente le cache local des sections) alors que les suites historiques
/// stubbent `getFeed`. On rétablit ici la délégation que la vraie classe fait
/// dans l'autre sens : un `when(() => feedRepo.getFeed(…))` reste la seule
/// chose à écrire, et `raw: null` garde le cache **inerte** (aucune de ces
/// suites ne teste la persistance ; celles qui la testent stubbent
/// `getFeedWithRaw` directement).
class MockFeedRepository extends Mock implements FeedRepository {
  @override
  Future<FeedRawResult> getFeedWithRaw({
    int page = 1,
    int limit = 20,
    String? contentType,
    bool savedOnly = false,
    String? mode,
    String? theme,
    String? topic,
    bool hasNote = false,
    String? sourceId,
    String? entity,
    String? keyword,
    bool includeUnfollowed = false,
    bool serein = false,
    bool personalized = false,
    bool followedOnly = false,
    bool forceFresh = false,
  }) async =>
      (
        // Exactement les 7 paramètres que passe le fan-out de la Tournée —
        // et donc ceux que matchent les `when(…)` des suites. En repasser
        // d'autres (même à leur valeur par défaut) ferait échouer le matcher
        // mocktail : `Invocation.namedArguments` ne contient que les arguments
        // **explicitement** fournis.
        feed: await getFeed(
          page: page,
          limit: limit,
          theme: theme,
          topic: topic,
          sourceId: sourceId,
          serein: serein,
          personalized: personalized,
        ),
        raw: null,
      );
}

/// Mock de [FluxContinuRepository] pour les suites Tournée.
///
/// Même raison que [MockFeedRepository] : la section veille est fetchée via
/// `getVeilleFeedItemsWithRaw` depuis le SWR in-day, alors que les suites
/// stubbent `getVeilleFeedItems`. Sans cette délégation, la veille disparaît
/// silencieusement de la Tournée dans les tests.
class MockFluxContinuRepository extends Mock implements FluxContinuRepository {
  @override
  Future<({FeedResponse feed, dynamic raw})> getVeilleFeedItemsWithRaw({
    int limit = 10,
    int offset = 0,
    bool serein = false,
  }) async =>
      (
        feed: await getVeilleFeedItems(
          limit: limit,
          offset: offset,
          serein: serein,
        ),
        raw: null,
      );
}
