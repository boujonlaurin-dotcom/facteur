import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/services/widget_service.dart';
import '../models/content_model.dart';
import '../repositories/feed_repository.dart';
import '../repositories/personalization_repository.dart';
import '../services/feed_cache_service.dart';
import '../services/read_sync_service.dart';
import '../../custom_topics/providers/personalization_provider.dart';
import '../../digest/providers/serein_toggle_provider.dart';
import '../../saved/providers/saved_feed_provider.dart';

/// Provider for the local feed cache (Hive-backed).
/// Returns null when the Hive box is not open (e.g. unit tests without Hive
/// init); callers must gracefully degrade to no-cache mode.
final feedCacheServiceProvider = Provider<FeedCacheService?>((ref) {
  return FeedCacheService.tryFromHive();
});

// Provider du repository
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FeedRepository(apiClient);
});

// Provider des données du feed (Infinite Scroll)
class FeedState {
  final List<Content> items;
  final List<FeedCarouselData> carousels;

  FeedState({required this.items, this.carousels = const []});
}

/// Snapshot capturé juste avant un refresh, pour permettre l'undo.
/// Contient l'état UI + le backup des `last_impressed_at` côté backend.
class FeedSnapshot {
  final List<Content> items;
  final List<FeedCarouselData> carousels;
  final int page;
  final bool hasNext;
  final List<PreviousImpression> impressionsBackup;

  const FeedSnapshot({
    required this.items,
    required this.carousels,
    required this.page,
    required this.hasNext,
    required this.impressionsBackup,
  });

  FeedSnapshot copyWith({List<PreviousImpression>? impressionsBackup}) =>
      FeedSnapshot(
        items: items,
        carousels: carousels,
        page: page,
        hasNext: hasNext,
        impressionsBackup: impressionsBackup ?? this.impressionsBackup,
      );
}

/// Snapshot du dernier refresh, utilisé par le bandeau undo.
/// `null` quand aucun undo n'est possible (pas de refresh récent ou undo déjà joué).
final feedUndoSnapshotProvider = StateProvider<FeedSnapshot?>((ref) => null);

/// Sélection de filtres en cours, exposée séparément du `feedProvider` pour que
/// l'UI (chips, tabs, badge du funnel) puisse réagir **dès le tap** sans
/// attendre la fin du refresh réseau. Les setters du [FeedNotifier] poussent
/// ici avant `await refresh()`.
/// Dimension de filtrage active du feed. Mutuellement exclusives : chaque
/// setter de [FeedNotifier] annule les autres.
enum FeedFilterKind { keyword, source, theme, topic, entity }

class FeedFilterSelection {
  final String? sourceId;
  final String? topic;
  final String? theme;
  final String? entity;
  final String? keyword;

  /// Recherche élargie aux sources non suivies (story 30.1). Fait partie de la
  /// sélection — et pas seulement de l'état interne du notifier — parce que
  /// l'UI doit se redessiner quand seul ce drapeau change (même mot-clé, mais
  /// périmètre différent).
  final bool includeUnfollowed;

  const FeedFilterSelection({
    this.sourceId,
    this.topic,
    this.theme,
    this.entity,
    this.keyword,
    this.includeUnfollowed = false,
  });

  static const empty = FeedFilterSelection();

  int get activeCount {
    var c = 0;
    if (sourceId != null) c++;
    if (keyword != null && keyword!.isNotEmpty) c++;
    return c;
  }

  /// Vrai dès qu'**un** filtre est posé, quel qu'il soit. Distinct de
  /// [activeCount], qui ne compte que source + mot-clé (badge du funnel).
  bool get hasAnyFilter => activeKind != null;

  /// Nature du filtre actif — les dimensions sont mutuellement exclusives
  /// (chaque setter du notifier annule les autres). `null` = flux non filtré.
  FeedFilterKind? get activeKind {
    if (keyword != null && keyword!.trim().isNotEmpty) {
      return FeedFilterKind.keyword;
    }
    if (sourceId != null) return FeedFilterKind.source;
    if (theme != null) return FeedFilterKind.theme;
    if (entity != null) return FeedFilterKind.entity;
    if (topic != null) return FeedFilterKind.topic;
    return null;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FeedFilterSelection &&
          sourceId == other.sourceId &&
          topic == other.topic &&
          theme == other.theme &&
          entity == other.entity &&
          keyword == other.keyword &&
          includeUnfollowed == other.includeUnfollowed;

  @override
  int get hashCode =>
      Object.hash(sourceId, topic, theme, entity, keyword, includeUnfollowed);
}

final feedFilterSelectionProvider = StateProvider<FeedFilterSelection>(
  (ref) => FeedFilterSelection.empty,
);

final _feedFilterSelectionOwnerProvider = StateProvider<String?>((ref) => null);

/// `true` tant qu'un refresh feed est en vol (filter change, serein toggle,
/// pull-to-refresh). Permet d'afficher un loader partagé sur les deux écrans
/// qui consomment `feedProvider` (FeedScreen + Explorer du FluxContinu).
final feedRefreshingProvider = StateProvider<bool>((ref) => false);

// Provider des données du feed (Infinite Scroll + Briefing)
final feedProvider = AsyncNotifierProvider<FeedNotifier, FeedState>(() {
  return FeedNotifier();
});

class _FeedAuthGate {
  final String? userId;
  final bool isAuthenticated;
  final bool isEmailConfirmed;
  final bool needsOnboarding;

  const _FeedAuthGate({
    required this.userId,
    required this.isAuthenticated,
    required this.isEmailConfirmed,
    required this.needsOnboarding,
  });

  factory _FeedAuthGate.fromAuthState(AuthState state) {
    return _FeedAuthGate(
      userId: state.user?.id,
      isAuthenticated: state.isAuthenticated,
      isEmailConfirmed: state.isEmailConfirmed,
      needsOnboarding: state.needsOnboarding,
    );
  }

  bool get canFetch =>
      isAuthenticated && userId != null && isEmailConfirmed && !needsOnboarding;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is _FeedAuthGate &&
          userId == other.userId &&
          isAuthenticated == other.isAuthenticated &&
          isEmailConfirmed == other.isEmailConfirmed &&
          needsOnboarding == other.needsOnboarding;

  @override
  int get hashCode =>
      Object.hash(userId, isAuthenticated, isEmailConfirmed, needsOnboarding);
}

class FeedNotifier extends AsyncNotifier<FeedState> {
  // Internal state for pagination
  int _page = 1;
  static const int _limit = 20;

  /// R5.1 — minimum age (seconds) of a cache hit before we trigger a
  /// silent background revalidation. Below this, the backend's own 30 s
  /// page-1 cache would just echo the same payload — saves a round-trip
  /// and contributes to the / api/feed/ amplification problem documented
  /// in `docs/bugs/bug-infinite-load-requests.md` (Round 5).
  static const int _silentRevalSkipSeconds = 60;
  bool _hasNext = true;
  bool _isLoadingMore = false;
  String? _selectedFilter;
  String? _selectedTheme;
  String? _selectedTopic;
  String? _selectedSourceId;
  String? _selectedEntity;
  String? _selectedKeyword;
  bool _includeUnfollowed = false;
  final Set<String> _consumedContentIds =
      {}; // Track content being animated out

  // Unfiltered snapshot — tab badges need counts across all topics, not just
  // the currently filtered subset.
  List<Content> _globalItems = [];

  Timer? _widgetPushDebounce;
  String? _lastWidgetPushSignature;
  DateTime? _lastWidgetPushAt;
  static const Duration _widgetPushDelay = Duration(seconds: 1);

  /// Buffer dédié au payload widget, **découplé** de la liste visible de
  /// Flâner.
  ///
  /// Le widget était alimenté par `state.items`, qui *rétrécit* au fil de la
  /// lecture (overlay `_consumedContentIds`) : après quelques articles lus, il
  /// ne restait que ~9 lignes sur l'écran d'accueil, et rien ne reconstituait
  /// la profondeur. Le buffer est alimenté en **union** (dédup par id, les
  /// arrivées fraîches en tête) et ne perd jamais d'entrée autrement que par
  /// éviction au-delà de [_widgetFluxCap].
  /// Cf. docs/bugs/bug-widget-fiabilite.md (C5).
  final List<Content> _widgetBuffer = [];

  /// Péremption du payload widget : au-delà, on re-pousse même à signature
  /// identique (l'utilisateur voit au moins des horodatages rafraîchis et le
  /// widget ne peut pas geler indéfiniment sur un cache figé).
  static const Duration _widgetPushMaxAge = Duration(hours: 6);

  // Cap mirrored to the Kotlin RemoteViewsFactory's MAX_ROWS_FLUX. The
  // widget runs without thumbnails in Flux, so 80 rows fit well under the
  // Binder IPC ceiling.
  static const int _widgetFluxCap = 80;
  // Max additional pages fetched purely to feed the widget. Keeps the
  // prefetch chain bounded even if the backend keeps reporting hasNext.
  static const int _widgetPrefetchMaxPages = 4;
  bool _widgetDepthFillInProgress = false;

  /// Silence entre deux chaînes de remplissage de profondeur.
  ///
  /// Nécessaire depuis que `!_hasNext` n'est plus un motif d'abandon : un
  /// compte qui n'a tout simplement pas 80 articles disponibles ne verra
  /// **jamais** son buffer atteindre [_widgetFluxCap], et sans ce garde il
  /// relancerait jusqu'à [_widgetPrefetchMaxPages] appels `/api/feed/` à
  /// chaque build du feed et à chaque retour de premier plan — exactement
  /// l'amplification documentée dans `docs/bugs/bug-infinite-load-requests.md`.
  static const Duration _widgetDepthFillCooldown = Duration(minutes: 30);
  DateTime? _lastWidgetDepthFillAt;

  bool get isLoadingMore => _isLoadingMore;
  bool get hasNext => _hasNext;
  String? get selectedFilter => _selectedFilter;
  String? get selectedTheme => _selectedTheme;
  String? get selectedTopic => _selectedTopic;
  String? get selectedSourceId => _selectedSourceId;
  String? get selectedEntity => _selectedEntity;
  String? get selectedKeyword => _selectedKeyword;
  List<Content> get globalItems => _globalItems;

  /// True quand l'onglet actif est un onglet de découverte (sujet / thème /
  /// entité). Le bloc principal est alors restreint aux sources suivies
  /// (`followed_only`) pour un chargement rapide, le bloc « Explorer » charge
  /// les sources non-suivies en parallèle. Source/mot-clé/vue par défaut → false.
  bool get _discoveryFiltered =>
      _selectedTopic != null ||
      _selectedTheme != null ||
      _selectedEntity != null;

  bool get _isUnfiltered =>
      _selectedFilter == null &&
      _selectedTopic == null &&
      _selectedTheme == null &&
      _selectedSourceId == null &&
      _selectedKeyword == null &&
      _selectedEntity == null;

  @override
  FutureOr<FeedState> build() async {
    listenSelf((previous, next) {
      next.whenData((data) => _scheduleWidgetPush(data.items));
    });
    ref.onDispose(() {
      _widgetPushDebounce?.cancel();
    });

    // Watch only the auth identity/gates that can affect feed access.
    // JWT rotations update AuthState.lastTokenRefreshAt, but must not rebuild
    // this notifier because rebuilds preserve scroll/list context.
    final authGate = ref.watch(
      authStateProvider.select(_FeedAuthGate.fromAuthState),
    );

    final selectionOwner = ref.read(_feedFilterSelectionOwnerProvider);

    if (!authGate.canFetch) {
      if (authGate.userId == null) {
        _resetFiltersToEmpty(syncSelectionProvider: true);
        _setSelectionOwner(null);
        FeedRepository.clearDefaultViewCache();
        _resetWidgetBuffer();
      } else if (selectionOwner != null && selectionOwner != authGate.userId) {
        _resetFiltersToEmpty(syncSelectionProvider: true);
        _setSelectionOwner(authGate.userId);
        FeedRepository.clearDefaultViewCache();
        _resetWidgetBuffer();
      }
      return FeedState(items: []);
    }

    if (selectionOwner != null && selectionOwner != authGate.userId) {
      FeedRepository.clearDefaultViewCache();
      _resetFiltersToEmpty(syncSelectionProvider: true);
      _setSelectionOwner(authGate.userId);
      _resetWidgetBuffer();
    } else {
      if (selectionOwner == null) {
        _setSelectionOwner(authGate.userId);
      }
      _restoreFiltersFromSelection();
    }

    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;

    // NB: serein toggle is observed in feed_screen.dart (which wraps the
    // refresh in a loading indicator). Listening here as well would cause
    // duplicate concurrent refreshes and race conditions on the feed state.

    // Stale-while-revalidate: if we have a fresh cached default feed (page 1,
    // no filters, serein-agnostic snapshot), paint it instantly and kick off
    // a silent refresh so the next frame is up-to-date. This is the main
    // lever for the "feed takes 4-5s on open" UX issue — subsequent opens in
    // the same 10-minute window become near-instant.
    final userId = authGate.userId!;
    final cache = ref.read(feedCacheServiceProvider);
    final isSerein = ref.read(sereinToggleProvider).enabled;
    final cacheVariant = _cacheVariantForSerein(isSerein);
    final cached = cache?.readRaw(userId, variant: cacheVariant);
    if (cached != null && cached.isFresh) {
      try {
        final parsed = FeedRepository.parseFeedData(
          data: cached.data,
          page: 1,
          limit: _limit,
        );
        _hasNext = parsed.pagination.hasNext && parsed.items.isNotEmpty;
        // R5.1 — Skip silent revalidation when the cache is very fresh.
        // The backend now caches `/api/feed/?page=1` for 30 s, so a
        // revalidation < 60 s after the last fetch would just hit the
        // server cache and bring no new data — wasted round-trip + extra
        // burst on the API. Past 60 s we still revalidate to keep the
        // stale-while-revalidate UX intact.
        final ageSeconds = DateTime.now().difference(cached.savedAt).inSeconds;
        if (ageSeconds >= _silentRevalSkipSeconds) {
          _scheduleSilentRevalidation();
        }
        // Le patch disque du statut consommé (patchContentStatus) est
        // best-effort/asynchrone et peut être en retard sur le set durable —
        // on superpose pour garantir le badge « Lu » (cf. _overlayConsumed).
        final overlaid = _overlayConsumed(parsed.items, parsed.carousels);
        _globalItems = overlaid.items;
        print(
          '[PERF] feedProvider.build(): cache hit (${overlaid.items.length} items, age=${ageSeconds}s, silent_reval=${ageSeconds >= _silentRevalSkipSeconds})',
        );
        unawaited(_prefetchForWidget(overlaid.items));
        return FeedState(items: overlaid.items, carousels: overlaid.carousels);
      } catch (e) {
        // Corrupted cache or schema drift — drop silently and fall through.
        print('FeedNotifier: cached feed parse failed, evicting: $e');
        await cache?.clearForUser(userId, variant: cacheVariant);
      }
    }

    // Fetch initial page
    final sw = Stopwatch()..start();
    final response = await _fetchPage(page: 1);
    sw.stop();
    print(
      '[PERF] feedProvider.build(): ${sw.elapsedMilliseconds}ms (${response.items.length} items)',
    );

    // Cold-load : le set consommé peut déjà être réamorcé depuis la file
    // durable Hive (flushCurrentUser au boot) avant que cette première page
    // réseau — encore `unseen` — n'arrive. On superpose pour ne pas repeindre
    // un article lu en non-lu (cf. _overlayConsumed).
    final overlaid = _overlayConsumed(response.items, response.carousels);
    _globalItems = overlaid.items;
    unawaited(_prefetchForWidget(overlaid.items));
    return FeedState(items: overlaid.items, carousels: overlaid.carousels);
  }

  /// Ré-applique le statut « consommé » sur une liste fraîchement fetchée
  /// (réseau/cache) pour qu'un reload n'efface pas le badge « Lu » tant que le
  /// POST backend `/status` n'a pas abouti.
  ///
  /// Source d'autorité = le Set durable en mémoire [consumedContentIdsProvider]
  /// (alimenté par [ReadSyncService.markConsumed] dès l'ouverture d'un article)
  /// **∪** les ids déjà `consumed` dans l'état courant (filet pour une course
  /// tap → réponse réseau). On élargit volontairement au provider car l'état
  /// courant a pu être vidé par un refresh antérieur.
  ({List<Content> items, List<FeedCarouselData> carousels}) _overlayConsumed(
    List<Content> items,
    List<FeedCarouselData> carousels,
  ) {
    final currentState = state.value;
    final consumedIds = <String>{
      ...ref.read(consumedContentIdsProvider),
      ...?(currentState?.items
          .where((c) => c.status == ContentStatus.consumed)
          .map((c) => c.id)),
      ...?(currentState?.carousels.expand(
        (carousel) => carousel.items
            .where((c) => c.status == ContentStatus.consumed)
            .map((c) => c.id),
      )),
    };
    if (consumedIds.isEmpty) {
      return (items: items, carousels: carousels);
    }
    Content preserve(Content c) => consumedIds.contains(c.id)
        ? c.copyWith(status: ContentStatus.consumed)
        : c;
    return (
      items: items.map(preserve).toList(),
      carousels: carousels
          .map((car) => car.copyWith(items: car.items.map(preserve).toList()))
          .toList(),
    );
  }

  /// Fire-and-forget background refresh triggered after a cache hit. Keeps
  /// the user's scroll position intact; a failure is silent (the stale cache
  /// stays visible until the next interaction).
  void _scheduleSilentRevalidation() {
    scheduleMicrotask(() async {
      try {
        final response = await _fetchPage(page: 1);
        // Only overwrite if still the "default" view (no filter change in-flight)
        // and state hasn't been replaced by the user meanwhile (e.g. a manual
        // refresh completed first).
        if (_selectedFilter != null ||
            _selectedTheme != null ||
            _selectedTopic != null ||
            _selectedSourceId != null ||
            _selectedEntity != null ||
            _selectedKeyword != null) {
          return;
        }
        // Preserve consumed status for items that the user marked while the API
        // call was in flight (race: tap → markContentAsConsumed sets optimistic
        // state before response arrives and would overwrite it). Source =
        // [consumedContentIdsProvider] ∪ état courant (cf. [_overlayConsumed]).
        final overlaid = _overlayConsumed(response.items, response.carousels);
        _globalItems = overlaid.items;
        state = AsyncData(
          FeedState(items: overlaid.items, carousels: overlaid.carousels),
        );
      } catch (e) {
        // Silent: user still sees the cached feed.
        print('FeedNotifier: silent revalidation failed: $e');
      }
    });
  }

  /// Re-amorce le widget home-screen à chaque ouverture/reprise de l'app :
  ///
  ///  - (a) re-pushe **immédiatement** le flux Flâner courant vers le widget
  ///    via [_scheduleWidgetPush] — répare un widget fraîchement épinglé ou un
  ///    payload vidé même si le contenu n'a pas changé ;
  ///  - (b) déclenche un [refresh] réseau quand [stale] (typiquement quand
  ///    l'app revient au premier plan après [flanerForegroundRefreshThreshold])
  ///    pour que le widget reçoive du contenu réellement frais.
  ///
  /// Le garde de signature de [_scheduleWidgetPush] évite tout churn de
  /// SharedPreferences si le contenu est identique.
  Future<void> ensureWidgetFresh({bool stale = false}) async {
    final items = state.value?.items ?? const <Content>[];
    if (items.isNotEmpty || _widgetBuffer.isNotEmpty) {
      _scheduleWidgetPush(items);
    }
    // Profondeur : si le buffer n'a jamais atteint 80 (widget « 9 articles »),
    // chaque reprise d'app est une occasion de la reconstituer.
    if (_isUnfiltered && _widgetBuffer.length < _widgetFluxCap) {
      unawaited(_prefetchForWidget(items));
    }
    if (stale) {
      // Best-effort, jamais fatal. Ce `refresh()` est appelé en
      // fire-and-forget depuis `app.dart` (`didChangeAppLifecycleState`) : une
      // erreur async qui remonte ici n'a aucun handler et finit en crash
      // *unhandled* via `PlatformDispatcher.onError` — c'est Sentry FLUTTER-1E
      // (401 au retour de premier plan). Rafraîchir le widget ne justifie
      // jamais de tuer l'app.
      try {
        await refresh();
      } catch (e, st) {
        // ignore: avoid_print
        print('FeedNotifier: ensureWidgetFresh refresh failed (ignored): $e');
        unawaited(
          Sentry.captureException(
            e,
            stackTrace: st,
            withScope: (scope) => scope.level = SentryLevel.warning,
          ),
        );
      }
    }
  }

  /// Push the current default feed to the home-screen widget. No-op when a
  /// filter/theme/source/etc. is active — only the canonical, unfiltered Flux
  /// is mirrored to the widget. Debounced + signature-guarded so optimistic
  /// taps and loadMore bursts don't churn SharedPreferences.
  ///
  /// [force] bypasses **both** the filter guard and the signature guard and
  /// pushes immediately (no debounce). It is reserved to the explicit
  /// home-screen widget refresh button ([refreshForWidget]): that gesture must
  /// never be a silent no-op, even when the payload is byte-identical to the
  /// last push or a Flâner filter is active in-app. Callers on the [force]
  /// path are responsible for passing the canonical *unfiltered* items.
  void _scheduleWidgetPush(List<Content> items, {bool force = false}) {
    if (!force && !_isUnfiltered) return;
    final slice = mergeIntoWidgetBuffer(items);
    if (slice.isEmpty) return;
    // Signature sur **tous** les ids : l'ancienne (`len|first|last`) ne voyait
    // pas un réordonnancement du milieu et gelait le widget, tout en laissant
    // passer un rétrécissement (len change) sans jamais le réparer.
    final signature = '${slice.length}|${slice.map((c) => c.id).join(',')}';
    final lastAt = _lastWidgetPushAt;
    final expired =
        lastAt == null || DateTime.now().difference(lastAt) >= _widgetPushMaxAge;
    if (!force && !expired && signature == _lastWidgetPushSignature) return;
    _widgetPushDebounce?.cancel();
    void push() {
      _lastWidgetPushSignature = signature;
      _lastWidgetPushAt = DateTime.now();
      WidgetService.updateWidget(feedItems: slice);
    }

    if (force) {
      // Synchronous push (no Timer) so the widget repaints before the
      // deep-link handler returns — Timer(Duration.zero) would still defer.
      push();
    } else {
      _widgetPushDebounce = Timer(_widgetPushDelay, push);
    }
  }

  /// Fusionne [incoming] dans [_widgetBuffer] : union dédupliquée par `id`,
  /// **triée par date de publication décroissante**, capée à
  /// [_widgetFluxCap]. Retourne le buffer résultant.
  ///
  /// Conséquence voulue : un article lu dans l'app disparaît de `state.items`
  /// mais **reste** dans le widget jusqu'à être évincé par du contenu plus
  /// récent. Le compteur du widget ne descend plus quand on lit.
  ///
  /// Le tri est explicite : l'union naïve « fraîchement fetché d'abord, ancien
  /// buffer derrière » donnait un ordre d'**arrivée réseau**, pas un ordre
  /// chronologique — visible dès la première fusion de fond (une page de 20
  /// posée devant un buffer de 80). Le widget doit refléter Flâner, qui est
  /// chronologique. Le cap s'applique **après** le tri, sinon on jetait des
  /// articles récents au profit d'anciens simplement arrivés plus tôt.
  ///
  /// Une entrée sans date connue ([Content.publishedAtRaw] nul) est conservée
  /// mais reléguée en fin : le serveur a omis la date, ce n'est pas une raison
  /// de perdre l'article ni de le hisser en tête.
  @visibleForTesting
  List<Content> mergeIntoWidgetBuffer(List<Content> incoming) {
    final union = <({Content item, int index})>[];
    final seen = <String>{};
    for (final c in [...incoming, ..._widgetBuffer]) {
      if (seen.add(c.id)) union.add((item: c, index: union.length));
    }
    // Le rang d'entrée départage les ex æquo — `incoming` d'abord, puis
    // l'ancien buffer. `List.sort` n'est pas stable en Dart : sans ce
    // départage, un lot d'articles sans date se réordonnait à chaque fusion.
    union.sort((a, b) {
      final da = a.item.publishedAtRaw;
      final db = b.item.publishedAtRaw;
      if (da != null && db != null) {
        final byDate = db.compareTo(da);
        if (byDate != 0) return byDate;
      } else if (da == null && db != null) {
        return 1;
      } else if (da != null && db == null) {
        return -1;
      }
      return a.index.compareTo(b.index);
    });
    final merged =
        union.take(_widgetFluxCap).map((e) => e.item).toList(growable: false);
    _widgetBuffer
      ..clear()
      ..addAll(merged);
    return List<Content>.unmodifiable(merged);
  }

  /// Vide le buffer widget (logout / changement d'utilisateur) : le compte
  /// suivant ne doit jamais hériter du flux du précédent.
  void _resetWidgetBuffer() {
    _widgetBuffer.clear();
    _lastWidgetPushSignature = null;
    _lastWidgetPushAt = null;
    _lastWidgetDepthFillAt = null;
  }

  /// Prefetch additional pages purely to feed the widget. Calls the repository
  /// directly so the in-app feed state (`state.value.items`, `_hasNext`, `_page`)
  /// is never mutated — pages 2-3 fetched here only land in the widget payload.
  ///
  /// Aborts silently if a filter becomes active mid-flight or if the chain is
  /// already running. Bounded by [_widgetPrefetchMaxPages], [_widgetFluxCap] et
  /// [_widgetDepthFillCooldown] — sauf [force] (geste utilisateur explicite).
  Future<void> _prefetchForWidget(
    List<Content> initialItems, {
    bool force = false,
  }) async {
    if (!_isUnfiltered) return;
    if (_widgetDepthFillInProgress) return;
    // On raisonne sur le buffer widget, pas sur la page qu'on vient de
    // recevoir : c'est lui qui doit atteindre 80. `_hasNext` n'est PLUS un
    // motif d'abandon — il décrit la pagination *visible* de Flâner, qui peut
    // être épuisée alors que le widget n'a que 9 lignes. Les vraies bornes
    // restent [_widgetPrefetchMaxPages] et [_widgetFluxCap].
    final seeded = mergeIntoWidgetBuffer(initialItems);
    if (seeded.length >= _widgetFluxCap) return;
    final lastFill = _lastWidgetDepthFillAt;
    if (!force &&
        lastFill != null &&
        DateTime.now().difference(lastFill) < _widgetDepthFillCooldown) {
      return;
    }

    _widgetDepthFillInProgress = true;
    _lastWidgetDepthFillAt = DateTime.now();
    try {
      final buffer = List<Content>.from(seeded);
      final existingIds = Set<String>.from(buffer.map((c) => c.id));
      final repository = ref.read(feedRepositoryProvider);
      final isSerein = ref.read(sereinToggleProvider).enabled;

      // Page 1 is already in [initialItems] — start at 2.
      var probePage = 2;
      var attempts = 0;
      while (buffer.length < _widgetFluxCap &&
          attempts < _widgetPrefetchMaxPages) {
        if (!_isUnfiltered) return;
        attempts++;
        try {
          final response = await repository.getFeed(
            page: probePage,
            limit: _limit,
            mode: null,
            theme: null,
            topic: null,
            sourceId: null,
            entity: null,
            keyword: null,
            includeUnfollowed: false,
            serein: isSerein,
          );
          final hasMore =
              response.pagination.hasNext && response.items.isNotEmpty;
          for (final c in response.items) {
            if (existingIds.add(c.id)) {
              buffer.add(c);
              if (buffer.length >= _widgetFluxCap) break;
            }
          }
          probePage++;
          if (!hasMore) break;
        } catch (e) {
          // Best-effort prefetch: a failed extra page must never bubble up.
          // ignore: avoid_print
          print('FeedNotifier: widget prefetch page $probePage failed: $e');
          break;
        }
      }

      if (!_isUnfiltered) return;
      _scheduleWidgetPush(buffer);
    } finally {
      _widgetDepthFillInProgress = false;
    }
  }

  Future<void> setFilter(String? filter) async {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    _selectedTheme = null; // Filters are mutually exclusive
    _selectedTopic = null;
    _selectedSourceId = null;
    _selectedEntity = null;
    _selectedKeyword = null;
    _includeUnfollowed = false;
    _syncSelectionProvider();
    await refresh();
  }

  Future<void> setTheme(String? theme) async {
    if (_selectedTheme == theme) return;
    _selectedTheme = theme;
    _selectedFilter = null;
    _selectedTopic = null;
    _selectedSourceId = null;
    _selectedEntity = null;
    _selectedKeyword = null;
    _includeUnfollowed = false;
    _syncSelectionProvider();
    await refresh();
  }

  Future<void> setTopic(String? topic) async {
    if (_selectedTopic == topic) return;
    _selectedTopic = topic;
    _selectedFilter = null;
    _selectedTheme = null;
    _selectedSourceId = null;
    _selectedEntity = null;
    _selectedKeyword = null;
    _includeUnfollowed = false;
    _syncSelectionProvider();
    await refresh();
  }

  Future<void> setEntity(String? entity) async {
    if (_selectedEntity == entity) return;
    _selectedEntity = entity;
    _selectedFilter = null;
    _selectedTheme = null;
    _selectedTopic = null;
    _selectedSourceId = null;
    _selectedKeyword = null;
    _includeUnfollowed = false;
    _syncSelectionProvider();
    await refresh();
  }

  Future<void> setKeyword(
    String? keyword, {
    bool includeUnfollowed = false,
  }) async {
    if (_selectedKeyword == keyword &&
        _includeUnfollowed == includeUnfollowed) {
      return;
    }
    _selectedKeyword = keyword;
    _includeUnfollowed = keyword != null ? includeUnfollowed : false;
    _selectedFilter = null;
    _selectedTheme = null;
    _selectedTopic = null;
    _selectedSourceId = null;
    _selectedEntity = null;
    _syncSelectionProvider();
    await refresh();
  }

  /// Vide **toutes** les dimensions de filtrage en un seul refresh.
  ///
  /// Enchaîner `setTopic(null)` + `setTheme(null)` + … marchait par accident
  /// (chaque setter annule déjà les autres, donc les suivants sortaient en
  /// no-op), mais obligeait chaque appelant à connaître la liste des
  /// dimensions — d'où la dérive documentée dans `feed_filter_bar.dart`
  /// (« on remet aussi `setSource(null)` — oublié historiquement »).
  Future<void> clearFilters() async {
    final selection = ref.read(feedFilterSelectionProvider);
    if (!selection.hasAnyFilter && _selectedFilter == null) return;
    _resetFiltersToEmpty(syncSelectionProvider: false);
    _syncSelectionProvider();
    await refresh();
  }

  Future<void> setSource(String? sourceId) async {
    if (_selectedSourceId == sourceId) return;
    _selectedSourceId = sourceId;
    _selectedFilter = null;
    _selectedTheme = null;
    _selectedTopic = null;
    _selectedEntity = null;
    _selectedKeyword = null;
    _includeUnfollowed = false;
    _syncSelectionProvider();
    await refresh();
  }

  FeedCacheVariant _cacheVariantForSerein(bool isSerein) =>
      isSerein ? FeedCacheVariant.serein : FeedCacheVariant.normal;

  void _restoreFiltersFromSelection() {
    final selection = ref.read(feedFilterSelectionProvider);
    _selectedFilter = null;
    _selectedSourceId = selection.sourceId;
    _selectedTopic = selection.topic;
    _selectedTheme = selection.theme;
    _selectedEntity = selection.entity;
    _selectedKeyword = selection.keyword;
    // Le périmètre élargi fait partie de la sélection restaurée : sans ça, un
    // rebuild du notifier (changement d'auth, invalidation) rétrécissait
    // silencieusement une recherche « toutes sources » aux seules sources
    // suivies, en gardant le mot-clé affiché.
    _includeUnfollowed = selection.includeUnfollowed;
  }

  void _resetFiltersToEmpty({required bool syncSelectionProvider}) {
    _selectedFilter = null;
    _selectedTheme = null;
    _selectedTopic = null;
    _selectedSourceId = null;
    _selectedEntity = null;
    _selectedKeyword = null;
    _includeUnfollowed = false;
    if (syncSelectionProvider) {
      // Riverpod interdit de muter un autre provider pendant le build : on
      // diffère donc le reset au prochain microtick.
      scheduleMicrotask(_syncSelectionProvider);
    }
  }

  void _setSelectionOwner(String? userId) {
    scheduleMicrotask(() {
      ref.read(_feedFilterSelectionOwnerProvider.notifier).state = userId;
    });
  }

  /// Pushes the current filter selection into [feedFilterSelectionProvider]
  /// so listeners (chips, tabs, funnel badge) rebuild **immediately** on tap,
  /// without waiting for the refresh round-trip.
  void _syncSelectionProvider() {
    ref.read(feedFilterSelectionProvider.notifier).state = FeedFilterSelection(
      sourceId: _selectedSourceId,
      topic: _selectedTopic,
      theme: _selectedTheme,
      entity: _selectedEntity,
      keyword: _selectedKeyword,
      includeUnfollowed: _includeUnfollowed,
    );
  }

  Future<FeedResponse> _fetchPage({
    required int page,
    bool forceFresh = false,
  }) async {
    final repository = ref.read(feedRepositoryProvider);
    final isSerein = ref.read(sereinToggleProvider).enabled;

    // Only the page-1 unfiltered view is cache-worthy: that's what the user
    // lands on after cold-open or tab switch. Normal and serein variants have
    // separate cache keys. Filtered views and paginated loads bypass the cache.
    final bool isDefaultView = page == 1 && _isUnfiltered;

    final cache = ref.read(feedCacheServiceProvider);
    if (isDefaultView && cache != null) {
      final result = await repository.getFeedWithRaw(
        page: page,
        limit: _limit,
        mode: _selectedFilter,
        theme: _selectedTheme,
        topic: _selectedTopic,
        sourceId: _selectedSourceId,
        entity: _selectedEntity,
        keyword: _selectedKeyword,
        serein: isSerein,
        forceFresh: forceFresh,
      );
      _hasNext = result.feed.pagination.hasNext && result.feed.items.isNotEmpty;
      // Persist in the background — cache write failures never block the UI.
      _persistDefaultFeedCache(
        result.raw,
        cache,
        variant: _cacheVariantForSerein(isSerein),
      );
      return result.feed;
    }

    final response = await repository.getFeed(
      page: page,
      limit: _limit,
      mode: _selectedFilter,
      theme: _selectedTheme,
      topic: _selectedTopic,
      sourceId: _selectedSourceId,
      entity: _selectedEntity,
      keyword: _selectedKeyword,
      includeUnfollowed: _includeUnfollowed,
      followedOnly: _discoveryFiltered,
      serein: isSerein,
    );

    // Hybrid pagination: trust the backend's `has_next` (based on the
    // total_candidates pool pre-diversification), but stop anyway if we got
    // an empty page so we don't loop forever if the backend says "more"
    // while returning nothing due to regroupement/clustering shrinkage.
    _hasNext = response.pagination.hasNext && response.items.isNotEmpty;

    return response;
  }

  /// Best-effort persistence of the default feed response for the current
  /// user. Silent on error (cache is a pure optimization).
  void _persistDefaultFeedCache(
    dynamic rawData,
    FeedCacheService cache, {
    required FeedCacheVariant variant,
  }) {
    final authState = ref.read(authStateProvider);
    final userId = authState.user?.id;
    if (userId == null) return;
    // Fire-and-forget: a failed write must never surface to the UI.
    unawaited(cache.saveRaw(userId, rawData, variant: variant));
  }

  Future<void> loadMore() async {
    // Prevent multiple calls or if no more data
    if (_isLoadingMore || !_hasNext || state.isLoading) return;

    _isLoadingMore = true;

    try {
      final nextPage = _page + 1;
      final response = await _fetchPage(page: nextPage);
      final newItems = response.items;

      if (newItems.isEmpty) {
        // `_fetchPage` already updated `_hasNext` via the hybrid check.
        return;
      }

      _page = nextPage;
      // Append new items to the existing list
      final currentItems = state.value?.items ?? [];
      final currentCarousels = state.value?.carousels ?? [];

      // Deduplicate by content ID: stale cache on page 1 + fresh API on page 2
      // can produce overlapping articles when new content was ingested in between.
      final existingIds = Set<String>.from(currentItems.map((c) => c.id));
      final dedupedNewItems =
          newItems.where((c) => !existingIds.contains(c.id)).toList();

      if (dedupedNewItems.isEmpty && newItems.isNotEmpty) {
        // All items were duplicates — pagination is fully misaligned (e.g. stale
        // cache vs. heavily updated candidate pool). Stop paging to avoid a loop.
        print(
          'FeedNotifier: loadMore page $nextPage fully deduplicated (${newItems.length} dupes), stopping pagination.',
        );
        _hasNext = false;
        return;
      }

      // Superpose le statut « Lu » optimiste sur les nouveaux items : une page
      // suivante peut contenir un article déjà lu dans la session mais encore
      // `unseen` côté backend (cf. _overlayConsumed).
      final overlaid = _overlayConsumed(
        [...currentItems, ...dedupedNewItems],
        currentCarousels,
      );
      state = AsyncData(
        FeedState(
          items: overlaid.items,
          carousels: overlaid.carousels, // Keep page 1 carousels
        ),
      );
    } catch (e) {
      // Don't replace state with AsyncError — that would wipe the existing
      // feed items on a transient page 2+ failure. Log and stop paging; the
      // user can pull-to-refresh to retry.
      print('FeedNotifier: loadMore failed on page ${_page + 1}: $e');
      _hasNext = false;
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> refresh() async {
    // Reset pagination
    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;

    // Ne pas émettre AsyncLoading — ça détruit le SliverList dans le screen
    // et reset la position de scroll. Le RefreshIndicator gère déjà le feedback visuel.
    // À la place : feedRefreshingProvider signale qu'un fetch est en vol →
    // sticky filter bar + écran legacy partagent le même LinearProgressIndicator.
    ref.read(feedRefreshingProvider.notifier).state = true;

    try {
      // R5.1 — pull-to-refresh / explicit refresh always bypasses the
      // repository-level dedupe so the user gesture produces a real network
      // call (the backend cache will still give a fast response, but the
      // user has the right to ask for fresh data).
      final response = await _fetchPage(page: 1, forceFresh: true);
      // Ré-applique le statut « Lu » optimiste : le backend renvoie encore
      // `unseen` tant que le POST /status n'a pas abouti — sans ça, un
      // pull-to-refresh / reprise d'app efface le badge (cf. _overlayConsumed).
      final overlaid = _overlayConsumed(response.items, response.carousels);
      if (_isUnfiltered) {
        _globalItems = overlaid.items;
      }
      state = AsyncData(
        FeedState(items: overlaid.items, carousels: overlaid.carousels),
      );
    } catch (e, stack) {
      // Recovery policy : ne JAMAIS figer le provider en AsyncError si on a
      // déjà des items à l'écran. Un AsyncError wipe `state.value` → tous les
      // handlers guardés sur `if (currentState == null) return;` deviennent
      // no-op (muteSource, toggleSave, etc.), ET un 2ème pull-to-refresh reste
      // coincé sur le même cycle d'échec car le provider semble « gelé ».
      //
      // On ré-émet donc l'état précédent pour débloquer les retries UI.
      // L'exception est re-throw via le catch du caller (FeedScreen._refresh
      // ne catch pas — le RefreshIndicator absorbe le throw et se ferme),
      // et les handlers optimistes peuvent re-tenter leur opération.
      //
      // Cf. docs/bugs/bug-feed-403-auth-recovery.md
      final previous = state.valueOrNull;
      if (previous != null) {
        // ignore: avoid_print
        print('FeedNotifier: refresh failed, keeping previous feed state: $e');
        state = AsyncData(previous);
      } else {
        // Premier chargement jamais abouti : AsyncError est la bonne
        // sémantique (le screen affichera un état d'erreur avec retry).
        // ignore: avoid_print
        print('FeedNotifier: refresh failed with no previous state: $e');
        state = AsyncError(e, stack);
      }
    } finally {
      ref.read(feedRefreshingProvider.notifier).state = false;
    }
  }

  /// Explicit refresh path for the home-screen widget's refresh button
  /// (`io.supabase.facteur://feed?refresh=1`).
  ///
  /// The ambient [refresh] + [_scheduleWidgetPush] chain is deliberately
  /// conservative: it skips the widget push under an active Flâner filter, when
  /// the content signature is unchanged, or on network error — which makes the
  /// button feel like a no-op precisely when the widget is stuck. This method
  /// guarantees the button always re-pushes the canonical **unfiltered** Flux:
  ///
  ///  1. Fetches a fresh unfiltered page 1 (respecting the Serein toggle),
  ///     without disturbing any in-app filter/scroll state.
  ///  2. Force-pushes it to the widget, bypassing the filter + signature guards.
  ///  3. Restores widget depth (up to 80) via [_prefetchForWidget].
  ///  4. On network failure, still force-pushes the last known unfiltered feed
  ///     ([_globalItems]) so the widget is never left silently stale.
  ///
  /// Il n'y a plus qu'un côté à réparer : le widget est un miroir de Flâner
  /// (cf. docs/bugs/bug-widget-flaner-android.md). Ce chemin ne sert plus qu'au
  /// deep link `feed?refresh=1` hérité — le bouton 🔄 du widget rafraîchit
  /// désormais en place, via `homeWidgetBackgroundCallback`.
  Future<void> refreshForWidget() async {
    final isSerein = ref.read(sereinToggleProvider).enabled;
    List<Content> unfiltered = const <Content>[];
    try {
      final repository = ref.read(feedRepositoryProvider);
      final response = await repository.getFeed(
        page: 1,
        limit: _limit,
        serein: isSerein,
        forceFresh: true,
      );
      unfiltered = response.items;

      // Le snapshot non filtré est mis à jour, mais **jamais** `state`.
      //
      // Le `state = AsyncData(...)` d'avant s'exécutait juste après le
      // `router.go('/flaner')` du deep-link : l'état visible était remplacé
      // pendant que `FlanerScreen` se montait, ce qui donnait le « le bouton
      // refresh plante Flâner ». Un tap sur le widget rafraîchit le *widget*,
      // pas l'écran sous le doigt — Flâner garde son scroll et son état.
      // Cf. docs/bugs/bug-widget-fiabilite.md (C4).
      if (_isUnfiltered && unfiltered.isNotEmpty) {
        final overlaid =
            _overlayConsumed(unfiltered, state.value?.carousels ?? const []);
        unfiltered = overlaid.items;
        _globalItems = overlaid.items;
      }
    } catch (e) {
      // Network failure: fall back to the last known unfiltered feed so the
      // refresh button still repaints the widget instead of leaving it stuck.
      // ignore: avoid_print
      print(
          'FeedNotifier: refreshForWidget fetch failed, using cached feed: $e');
    }

    final toPush = unfiltered.isNotEmpty ? unfiltered : _globalItems;
    if (toPush.isEmpty) return;
    _scheduleWidgetPush(toPush, force: true);
    // `force` : geste explicite de l'utilisateur, il court-circuite le cooldown
    // de profondeur (qui ne vise que les déclenchements ambiants).
    unawaited(_prefetchForWidget(toPush, force: true));
  }

  /// Refresh feed: mark visible articles (cards + carousel items qui sont
  /// pleinement apparus à l'écran) comme "déjà vus", puis re-fetch.
  ///
  /// Capture un snapshot de l'état UI + backup backend dans
  /// [feedUndoSnapshotProvider] pour permettre l'undo via [undoLastRefresh].
  /// Story 4.5b.
  Future<void> refreshArticlesWithSnapshot(
    Set<String> visibleContentIds,
  ) async {
    // Single owner of the snapshot lifecycle: always drop any prior value at
    // the start. We'll either replace it below (happy path) or leave it null
    // (empty visible set, backend failure) — never leak a stale snapshot that
    // the banner could resurrect on a later refresh.
    ref.read(feedUndoSnapshotProvider.notifier).state = null;

    final currentState = state.value;
    if (currentState == null) return;

    // Collect IDs from main feed items (non-consumed + visible)
    final mainIds = currentState.items
        .where(
          (c) =>
              c.status != ContentStatus.consumed &&
              visibleContentIds.contains(c.id),
        )
        .map((c) => c.id)
        .toSet();

    // Also include visible carousel items (carousels aren't in items[])
    final carouselIds = <String>{};
    for (final carousel in currentState.carousels) {
      for (final item in carousel.items) {
        if (visibleContentIds.contains(item.id)) {
          carouselIds.add(item.id);
        }
      }
    }

    final allIds = {...mainIds, ...carouselIds}.toList();

    if (allIds.isEmpty) {
      // Nothing viewed → plain refetch, no undo snapshot.
      await refresh();
      return;
    }

    // 1. Capture UI snapshot BEFORE calling backend
    final snapshot = FeedSnapshot(
      items: List<Content>.from(currentState.items),
      carousels: List<FeedCarouselData>.from(currentState.carousels),
      page: _page,
      hasNext: _hasNext,
      impressionsBackup: const [],
    );

    // 2. Call backend (returns previous_impressions for undo). If this fails,
    // we still refetch so the pull-to-refresh gesture feels responsive, but
    // we don't expose an undo banner because the server state is unchanged.
    try {
      final repository = ref.read(feedRepositoryProvider);
      final backups = await repository.refreshFeed(allIds);

      // 3. Store enriched snapshot for undo (only on success)
      ref.read(feedUndoSnapshotProvider.notifier).state = snapshot.copyWith(
        impressionsBackup: backups,
      );
    } catch (e) {
      print(
        'FeedNotifier: refreshArticlesWithSnapshot backend call failed: $e',
      );
    }

    // 4. Refetch page 1 (always — keeps the gesture responsive even on error)
    await refresh();
  }

  /// Annule le dernier refresh : restaure l'état UI précédent et rollback
  /// les `last_impressed_at` côté backend.
  ///
  /// Si aucun snapshot n'est disponible (expiré, déjà undo'd), no-op.
  /// Story 4.5b.
  Future<void> undoLastRefresh() async {
    final snapshot = ref.read(feedUndoSnapshotProvider);
    if (snapshot == null) return;

    // 1. Restore UI state optimistically
    _page = snapshot.page;
    _hasNext = snapshot.hasNext;
    state = AsyncData(
      FeedState(items: snapshot.items, carousels: snapshot.carousels),
    );

    // 2. Clear snapshot immediately so double-tap does nothing
    ref.read(feedUndoSnapshotProvider.notifier).state = null;

    // 3. Rollback backend (fire-and-forget — UI is already restored)
    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.undoRefresh(snapshot.impressionsBackup);
    } catch (e) {
      print('FeedNotifier: undoLastRefresh backend rollback failed: $e');
    }
  }

  /// Mark a single article as "already seen" — permanent strong penalty.
  Future<void> impressContent(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove from feed
    final updatedItems = List<Content>.from(currentState.items);
    updatedItems.removeWhere((c) => c.id == content.id);
    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.impressContent(content.id);
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  /// Mark an article as "already seen" by ID only (used from digest).
  Future<void> impressContentById(String contentId) async {
    final repository = ref.read(feedRepositoryProvider);
    await repository.impressContent(contentId);
  }

  /// T1: Update a content item inside carousel data (optimistic sync).
  List<FeedCarouselData> _updateCarouselItem(
    List<FeedCarouselData> carousels,
    String contentId,
    Content Function(Content) updater,
  ) {
    return carousels.map((carousel) {
      final hasItem = carousel.items.any((item) => item.id == contentId);
      if (!hasItem) return carousel;
      final updatedItems = carousel.items.map((item) {
        if (item.id == contentId) return updater(item);
        return item;
      }).toList();
      return carousel.copyWith(items: updatedItems);
    }).toList();
  }

  Future<void> toggleSave(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    final currentItems = currentState.items;
    final index = currentItems.indexWhere((c) => c.id == content.id);

    // Si l'index est -1, l'item a été archivé (ou absent)
    final bool currentlyInList = index != -1;
    final bool oldIsSaved =
        currentlyInList ? currentItems[index].isSaved : true;
    final bool newIsSaved = !oldIsSaved;

    final updatedItems = List<Content>.from(currentItems);

    if (newIsSaved) {
      if (currentlyInList) {
        updatedItems[index] = content.copyWith(isSaved: true);
      }
    } else {
      if (currentlyInList) {
        updatedItems[index] = content.copyWith(isSaved: false);
      }
    }

    // T1: Sync carousel items too
    final updatedCarousels = _updateCarouselItem(
      currentState.carousels,
      content.id,
      (c) => c.copyWith(isSaved: newIsSaved),
    );

    // Mise à jour optimiste immédiate
    state = AsyncData(
      FeedState(items: updatedItems, carousels: updatedCarousels),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.toggleSave(content.id, newIsSaved);
      // Invalidate SavedFeed so it refreshes when the user navigates there
      ref.invalidate(savedFeedProvider);
      // R5 fix — drop the 5s dedupe result so any subsequent fetch
      // (silent revalidation, cross-screen remount) sees the new isSaved.
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  Future<void> toggleLike(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    final currentItems = currentState.items;
    final index = currentItems.indexWhere((c) => c.id == content.id);

    final bool currentlyInList = index != -1;
    final bool oldIsLiked =
        currentlyInList ? currentItems[index].isLiked : true;
    final bool newIsLiked = !oldIsLiked;

    final updatedItems = List<Content>.from(currentItems);

    if (currentlyInList) {
      updatedItems[index] = content.copyWith(isLiked: newIsLiked);
    }

    // T1: Sync carousel items too
    final updatedCarousels = _updateCarouselItem(
      currentState.carousels,
      content.id,
      (c) => c.copyWith(isLiked: newIsLiked),
    );

    // Optimistic update
    state = AsyncData(
      FeedState(items: updatedItems, carousels: updatedCarousels),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.toggleLike(content.id, newIsLiked);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  Future<void> hideContent(Content content, HiddenReason reason) async {
    final currentState = state.value;
    if (currentState == null) return;

    final updatedItems = List<Content>.from(currentState.items);
    updatedItems.removeWhere((c) => c.id == content.id);

    // Optimistic remove
    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id, reason);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  /// Swipe-dismiss: hide without reason. Backend adjusts subtopic weights.
  Future<void> swipeDismiss(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    final updatedItems = List<Content>.from(currentState.items);
    updatedItems.removeWhere((c) => c.id == content.id);

    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      // Silent failure — optimistic remove stays
      print('FeedNotifier: swipeDismiss failed for ${content.id}: $e');
    }
  }

  /// Hides remotely while retaining the article in local state so the screen
  /// can replace its exact row with inline feedback.
  Future<void> markHiddenRemote(Content content) async {
    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      debugPrint(
        'FeedNotifier: markHiddenRemote failed for ${content.id}: $e',
      );
    }
  }

  /// Confirms removal after the inline feedback has been resolved.
  void confirmDismiss(String contentId) {
    removeFromState(contentId);
  }

  /// Cancels a remote hide while the retained local article stays in place.
  Future<void> undoHide(Content content) async {
    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.unhideContent(content.id);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      debugPrint('FeedNotifier: undoHide failed for ${content.id}: $e');
    }
  }

  /// Retrait local de l'item du state, sans appel API.
  ///
  /// À utiliser quand le hide a déjà été émis ailleurs (ex: résolution du
  /// FeedbackInline après un swipe-left, où `hideContent` a été appelé
  /// immédiatement et le banner inline a remplacé la carte en attente d'un
  /// CTA).
  void removeFromState(String contentId) {
    final currentState = state.value;
    if (currentState == null) return;
    final updatedItems = List<Content>.from(currentState.items)
      ..removeWhere((c) => c.id == contentId);
    state = AsyncData(
      FeedState(items: updatedItems, carousels: currentState.carousels),
    );
  }

  /// Undo a swipe-dismiss: re-insert article at original position.
  Future<void> undoSwipeDismiss(Content content, int originalIndex) async {
    final currentState = state.value;
    if (currentState == null) return;

    final updatedItems = List<Content>.from(currentState.items);
    final insertIndex = originalIndex.clamp(0, updatedItems.length);
    updatedItems.insert(insertIndex, content);

    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.unhideContent(content.id);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: undoSwipeDismiss failed for ${content.id}: $e');
    }
  }

  /// Swipe-dismiss + mute source combo (from banner "Moins de [Source]").
  Future<void> swipeDismissAndMuteSource(Content content) async {
    // Hide is already done by swipeDismiss or will be done here
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove all from this source
    final updatedItems = currentState.items
        .where((c) => c.source.id != content.source.id)
        .toList();
    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id);
    } catch (e) {
      print('FeedNotifier: swipeDismissAndMuteSource hide failed: $e');
    }

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteSource(content.source.id);
      ref.invalidate(personalizationProvider);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: swipeDismissAndMuteSource mute failed: $e');
    }
  }

  /// Swipe-dismiss + mute topic combo (from banner "Moins sur [Topic]").
  Future<void> swipeDismissAndMuteTopic(Content content, String topic) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove: the dismissed article + all articles matching this topic slug
    final updatedItems = currentState.items.where((c) {
      if (c.id == content.id) return false;
      return !c.topics.contains(topic);
    }).toList();
    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id);
    } catch (e) {
      print('FeedNotifier: swipeDismissAndMuteTopic hide failed: $e');
    }

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteTopic(topic);
      ref.invalidate(personalizationProvider);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: swipeDismissAndMuteTopic mute failed: $e');
    }
  }

  Future<void> muteSource(Content content) async {
    await muteSourceById(content.source.id);
  }

  Future<void> muteSourceById(String sourceId) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content from this source
    final updatedItems =
        currentState.items.where((c) => c.source.id != sourceId).toList();
    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteSource(sourceId);
      ref.invalidate(personalizationProvider);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: muteSourceById failed for $sourceId: $e');
    }
  }

  Future<void> muteTheme(String theme) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content from this theme
    final updatedItems =
        currentState.items.where((c) => c.source.theme != theme).toList();
    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteTheme(theme);
      ref.invalidate(personalizationProvider);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: muteTheme failed for $theme: $e');
    }
  }

  Future<void> muteTopic(String topic) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content matching this topic slug
    final updatedItems = currentState.items.where((c) {
      return !c.topics.contains(topic);
    }).toList();

    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteTopic(topic);
      ref.invalidate(personalizationProvider);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: muteTopic failed for $topic: $e');
    }
  }

  Future<void> muteEntity(String entityName) async {
    final currentState = state.value;
    if (currentState == null) return;

    final lowerName = entityName.toLowerCase();

    // Optimistic remove of all content mentioning this entity
    final updatedItems = currentState.items.where((c) {
      return !c.entities.any((e) => e.text.toLowerCase() == lowerName);
    }).toList();

    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteTopic(lowerName);
      ref.invalidate(personalizationProvider);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: muteEntity failed for $entityName: $e');
    }
  }

  Future<void> muteContentType(String contentType) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content matching this content type
    final updatedItems = currentState.items
        .where((c) => c.contentType.name != contentType)
        .toList();

    state = AsyncData(
      FeedState(
        items: updatedItems,
        carousels: state.value?.carousels ?? const [],
      ),
    );

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteContentType(contentType);
      ref.invalidate(personalizationProvider);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      print('FeedNotifier: muteContentType failed for $contentType: $e');
    }
  }

  /// Check if content is currently being consumed (animating out)
  bool isContentConsumed(String contentId) {
    return _consumedContentIds.contains(contentId);
  }

  /// Update a content item in the feed list (e.g. after detail screen changes).
  /// Preserves provider-managed fields like [status] (consumed marking).
  void updateContent(Content updated) {
    final currentState = state.value;
    if (currentState == null) return;

    final items = currentState.items.map((c) {
      if (c.id != updated.id) return c;
      return updated.copyWith(status: c.status);
    }).toList();

    final updatedCarousels = _updateCarouselItem(
      currentState.carousels,
      updated.id,
      (c) => updated.copyWith(status: c.status),
    );

    state = AsyncData(FeedState(items: items, carousels: updatedCarousels));
  }

  void markContentConsumedLocally(String contentId) {
    final currentState = state.value;
    if (currentState == null || contentId.isEmpty) return;

    final updatedItems = currentState.items
        .map(
          (c) => c.id == contentId
              ? c.copyWith(status: ContentStatus.consumed)
              : c,
        )
        .toList();
    final updatedCarousels = _updateCarouselItem(
      currentState.carousels,
      contentId,
      (c) => c.copyWith(status: ContentStatus.consumed),
    );
    state = AsyncData(
      FeedState(items: updatedItems, carousels: updatedCarousels),
    );
  }

  Future<void> markContentAsConsumed(Content content) async {
    markContentConsumedLocally(content.id);

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.updateContentStatus(content.id, ContentStatus.consumed);
      final userId = ref.read(authStateProvider).user?.id;
      if (userId != null) {
        final cache = ref.read(feedCacheServiceProvider);
        if (cache != null) {
          unawaited(
            cache.patchContentStatus(
              userId,
              content.id,
              ContentStatus.consumed,
              variant: FeedCacheVariant.normal,
            ),
          );
          unawaited(
            cache.patchContentStatus(
              userId,
              content.id,
              ContentStatus.consumed,
              variant: FeedCacheVariant.serein,
            ),
          );
        }
      }
    } catch (e) {
      // Silent failure, state is already updated optimistically
    }
  }
}
