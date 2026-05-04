import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../models/content_model.dart';
import '../repositories/feed_repository.dart';
import '../repositories/personalization_repository.dart';
import '../services/feed_cache_service.dart';
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

  FeedState({
    required this.items,
    this.carousels = const [],
  });
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

  FeedSnapshot copyWith({
    List<PreviousImpression>? impressionsBackup,
  }) =>
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

// Provider des données du feed (Infinite Scroll + Briefing)
final feedProvider = AsyncNotifierProvider<FeedNotifier, FeedState>(() {
  return FeedNotifier();
});

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

  bool get isLoadingMore => _isLoadingMore;
  bool get hasNext => _hasNext;
  String? get selectedFilter => _selectedFilter;
  String? get selectedTheme => _selectedTheme;
  String? get selectedTopic => _selectedTopic;
  String? get selectedSourceId => _selectedSourceId;
  String? get selectedEntity => _selectedEntity;
  String? get selectedKeyword => _selectedKeyword;

  @override
  FutureOr<FeedState> build() async {
    // Watch auth state to handle logout/user change
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      // R5.1 — drop the static repository-level dedupe state on logout
      // so the next user (or the same user after re-login) can't see a
      // stale payload from the previous session.
      FeedRepository.clearDefaultViewCache();
      return FeedState(items: []);
    }

    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;
    _selectedFilter = null; // Reset filter on build/rebuild
    _selectedTheme = null;
    _selectedTopic = null;
    _selectedSourceId = null;
    _selectedEntity = null;
    _selectedKeyword = null;

    // NB: serein toggle is observed in feed_screen.dart (which wraps the
    // refresh in a loading indicator). Listening here as well would cause
    // duplicate concurrent refreshes and race conditions on the feed state.

    // Stale-while-revalidate: if we have a fresh cached default feed (page 1,
    // no filters, serein-agnostic snapshot), paint it instantly and kick off
    // a silent refresh so the next frame is up-to-date. This is the main
    // lever for the "feed takes 4-5s on open" UX issue — subsequent opens in
    // the same 10-minute window become near-instant.
    final userId = authState.user!.id;
    final cache = ref.read(feedCacheServiceProvider);
    final isSerein = ref.read(sereinToggleProvider).enabled;
    final cached = (!isSerein) ? cache?.readRaw(userId) : null;
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
        print(
            '[PERF] feedProvider.build(): cache hit (${parsed.items.length} items, age=${ageSeconds}s, silent_reval=${ageSeconds >= _silentRevalSkipSeconds})');
        return FeedState(items: parsed.items, carousels: parsed.carousels);
      } catch (e) {
        // Corrupted cache or schema drift — drop silently and fall through.
        print('FeedNotifier: cached feed parse failed, evicting: $e');
        await cache?.clearForUser(userId);
      }
    }

    // Fetch initial page
    final sw = Stopwatch()..start();
    final response = await _fetchPage(page: 1);
    sw.stop();
    print('[PERF] feedProvider.build(): ${sw.elapsedMilliseconds}ms (${response.items.length} items)');

    return FeedState(items: response.items, carousels: response.carousels);
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
        // state before response arrives and would overwrite it).
        final currentState = state.value;
        final consumedIds = <String>{
          ...?(currentState?.items
              .where((c) => c.status == ContentStatus.consumed)
              .map((c) => c.id)),
          ...?(currentState?.carousels.expand((carousel) => carousel.items
              .where((c) => c.status == ContentStatus.consumed)
              .map((c) => c.id))),
        };
        Content preserve(Content c) => consumedIds.contains(c.id)
            ? c.copyWith(status: ContentStatus.consumed)
            : c;
        state = AsyncData(FeedState(
          items: response.items.map(preserve).toList(),
          carousels: response.carousels
              .map((car) =>
                  car.copyWith(items: car.items.map(preserve).toList()))
              .toList(),
        ));
      } catch (e) {
        // Silent: user still sees the cached feed.
        print('FeedNotifier: silent revalidation failed: $e');
      }
    });
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
    await refresh();
  }

  Future<void> setKeyword(String? keyword, {bool includeUnfollowed = false}) async {
    if (_selectedKeyword == keyword && _includeUnfollowed == includeUnfollowed) {
      return;
    }
    _selectedKeyword = keyword;
    _includeUnfollowed = keyword != null ? includeUnfollowed : false;
    _selectedFilter = null;
    _selectedTheme = null;
    _selectedTopic = null;
    _selectedSourceId = null;
    _selectedEntity = null;
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
    await refresh();
  }

  Future<FeedResponse> _fetchPage({
    required int page,
    bool forceFresh = false,
  }) async {
    final repository = ref.read(feedRepositoryProvider);
    final isSerein = ref.read(sereinToggleProvider).enabled;

    // Only the page-1 "default" view (no filters, serein off) is cache-worthy:
    // that's what the user lands on after cold-open or tab switch. Filtered
    // views and paginated loads bypass the cache entirely.
    final bool isDefaultView = page == 1 &&
        !isSerein &&
        _selectedFilter == null &&
        _selectedTheme == null &&
        _selectedTopic == null &&
        _selectedSourceId == null &&
        _selectedEntity == null &&
        _selectedKeyword == null;

    if (isDefaultView) {
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
          forceFresh: forceFresh);
      _hasNext = result.feed.pagination.hasNext && result.feed.items.isNotEmpty;
      // Persist in the background — cache write failures never block the UI.
      _persistDefaultFeedCache(result.raw);
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
        serein: isSerein);

    // Hybrid pagination: trust the backend's `has_next` (based on the
    // total_candidates pool pre-diversification), but stop anyway if we got
    // an empty page so we don't loop forever if the backend says "more"
    // while returning nothing due to regroupement/clustering shrinkage.
    _hasNext = response.pagination.hasNext && response.items.isNotEmpty;

    return response;
  }

  /// Best-effort persistence of the default feed response for the current
  /// user. Silent on error (cache is a pure optimization).
  void _persistDefaultFeedCache(dynamic rawData) {
    final authState = ref.read(authStateProvider);
    final userId = authState.user?.id;
    if (userId == null) return;
    final cache = ref.read(feedCacheServiceProvider);
    if (cache == null) return;
    // Fire-and-forget: a failed write must never surface to the UI.
    unawaited(cache.saveRaw(userId, rawData));
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

      state = AsyncData(FeedState(
        items: [...currentItems, ...newItems],
        carousels: currentCarousels, // Keep page 1 carousels
      ));
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

    try {
      // R5.1 — pull-to-refresh / explicit refresh always bypasses the
      // repository-level dedupe so the user gesture produces a real network
      // call (the backend cache will still give a fast response, but the
      // user has the right to ask for fresh data).
      final response = await _fetchPage(page: 1, forceFresh: true);
      state = AsyncData(FeedState(
        items: response.items,
        carousels: response.carousels,
      ));
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
        print(
            'FeedNotifier: refresh failed, keeping previous feed state: $e');
        state = AsyncData(previous);
      } else {
        // Premier chargement jamais abouti : AsyncError est la bonne
        // sémantique (le screen affichera un état d'erreur avec retry).
        // ignore: avoid_print
        print('FeedNotifier: refresh failed with no previous state: $e');
        state = AsyncError(e, stack);
      }
    }
  }

  /// Refresh feed: mark visible articles (cards + carousel items qui sont
  /// pleinement apparus à l'écran) comme "déjà vus", puis re-fetch.
  ///
  /// Capture un snapshot de l'état UI + backup backend dans
  /// [feedUndoSnapshotProvider] pour permettre l'undo via [undoLastRefresh].
  /// Story 4.5b.
  Future<void> refreshArticlesWithSnapshot(Set<String> visibleContentIds) async {
    // Single owner of the snapshot lifecycle: always drop any prior value at
    // the start. We'll either replace it below (happy path) or leave it null
    // (empty visible set, backend failure) — never leak a stale snapshot that
    // the banner could resurrect on a later refresh.
    ref.read(feedUndoSnapshotProvider.notifier).state = null;

    final currentState = state.value;
    if (currentState == null) return;

    // Collect IDs from main feed items (non-consumed + visible)
    final mainIds = currentState.items
        .where((c) =>
            c.status != ContentStatus.consumed &&
            visibleContentIds.contains(c.id))
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
      ref.read(feedUndoSnapshotProvider.notifier).state =
          snapshot.copyWith(impressionsBackup: backups);
    } catch (e) {
      print('FeedNotifier: refreshArticlesWithSnapshot backend call failed: $e');
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
    state = AsyncData(FeedState(
      items: snapshot.items,
      carousels: snapshot.carousels,
    ));

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
    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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
    state = AsyncData(FeedState(items: updatedItems, carousels: updatedCarousels));

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
    state = AsyncData(FeedState(items: updatedItems, carousels: updatedCarousels));

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
    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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

    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id);
      FeedRepository.clearDefaultViewCache();
    } catch (e) {
      // Silent failure — optimistic remove stays
      print('FeedNotifier: swipeDismiss failed for ${content.id}: $e');
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
    state = AsyncData(FeedState(
      items: updatedItems,
      carousels: currentState.carousels,
    ));
  }

  /// Undo a swipe-dismiss: re-insert article at original position.
  Future<void> undoSwipeDismiss(Content content, int originalIndex) async {
    final currentState = state.value;
    if (currentState == null) return;

    final updatedItems = List<Content>.from(currentState.items);
    final insertIndex = originalIndex.clamp(0, updatedItems.length);
    updatedItems.insert(insertIndex, content);

    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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
    final updatedItems =
        currentState.items.where((c) => c.source.id != content.source.id).toList();
    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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
    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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
    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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
    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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

    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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

    state = AsyncData(FeedState(items: updatedItems, carousels: state.value?.carousels ?? const []));

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

  Future<void> markContentAsConsumed(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    final feedIndex = currentState.items.indexWhere((c) => c.id == content.id);

    final updatedItems = List<Content>.from(currentState.items);
    if (feedIndex != -1) {
      updatedItems[feedIndex] =
          updatedItems[feedIndex].copyWith(status: ContentStatus.consumed);
    }

    final updatedCarousels = _updateCarouselItem(
      currentState.carousels,
      content.id,
      (c) => c.copyWith(status: ContentStatus.consumed),
    );

    state = AsyncData(FeedState(items: updatedItems, carousels: updatedCarousels));

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.updateContentStatus(content.id, ContentStatus.consumed);
      // Invalidate in-memory dedupe + Hive cache so the next fetch (silent
      // revalidation or cold start) returns fresh data with the correct status.
      FeedRepository.clearDefaultViewCache();
      final userId = ref.read(authStateProvider).user?.id;
      if (userId != null) {
        unawaited(ref.read(feedCacheServiceProvider)?.clearForUser(userId));
      }
    } catch (e) {
      // Silent failure, state is already updated optimistically
    }
  }
}
