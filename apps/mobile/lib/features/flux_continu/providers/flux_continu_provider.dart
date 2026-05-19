import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../digest/models/digest_models.dart';
import '../../digest/models/dual_digest_response.dart';
import '../../digest/providers/digest_provider.dart'
    show digestRepositoryProvider;
import '../../digest/providers/serein_toggle_provider.dart';
import '../../digest/repositories/digest_repository.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart' show feedRepositoryProvider;
import '../../feed/repositories/feed_repository.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../models/flux_continu_models.dart';
import '../repositories/flux_continu_repository.dart';
import '../utils/theme_color_mapping.dart';

/// Accent applied to the Essentiel section banner.
const Color _kEssentielAccent = Color(0xFFB0470A);

/// Accent applied to the Bonnes Nouvelles section banner.
const Color _kBonnesAccent = Color(0xFF2E7D32);

/// Illustration asset associated with each editorial section.
const String _kEssentielIllustration =
    'assets/notifications/facteur_avatar.png';
const String _kBonnesIllustration = 'assets/notifications/facteur_goodnews.png';
const String _kVeilleIllustration = 'assets/notifications/facteur_veille.png';

/// Blurbs rendered under each section title.
const String _kEssentielBlurb =
    "L'essentiel des actus les plus couvertes en France aujourd'hui, en privilégiant tes sources.";
const String _kBonnesBlurb = 'Un peu d\'amour, dans ce monde de brutes ?';
const String _kThemeBlurb =
    "Les derniers articles sur les sujets que tu suis le plus.";

/// Hard cap on the number of favorite theme sections rendered in the tournée.
/// Mirrors `kFavoriteCap = 3` in the my_interests provider — the value is
/// duplicated here only because the maps key by sectionKey and we slice the
/// favorite list during composition. Keep aligned with the backend constant.
const int _kMaxFavoriteSections = 3;

/// Prefix for the day-scoped SharedPreferences key that stores which sections
/// the user has already scrolled past today. Keys older than today are purged
/// at startup so a new day starts with every section expanded.
const String _kFoldedPrefsKeyPrefix = 'flux_continu_folded_';
const String _kClosingPrefsKeyPrefix = 'flux_continu_closing_dismissed_';

String _dayKey(DateTime day) => day.toIso8601String().substring(0, 10);

String _foldedPrefsKey(DateTime day) =>
    '$_kFoldedPrefsKeyPrefix${_dayKey(day)}';

String _closingPrefsKey(DateTime day) =>
    '$_kClosingPrefsKeyPrefix${_dayKey(day)}';

/// Riverpod provider for the Flux Continu V1.8 home screen.
///
/// Orchestrates three parallel API calls at mount, then up to three themed
/// feed calls once the user's favorites have been resolved. Holds an ordered
/// list of sections (already accounting for the serein swap) and a deduped
/// feed continuation to render below the closing card.
final fluxContinuProvider =
    AsyncNotifierProvider<FluxContinuNotifier, FluxContinuState>(
  FluxContinuNotifier.new,
);

class FluxContinuNotifier extends AsyncNotifier<FluxContinuState> {
  late DigestRepository _digestRepo;
  late FeedRepository _feedRepo;
  late FluxContinuRepository _fluxRepo;

  FluxSection? _essentiel;
  FluxSection? _bonnes;
  // Up to [_kMaxFavoriteSections] theme/topic sections, ordered to mirror
  // `userInterestsProvider.favorites`. Empty when the user has no favorites
  // — the tournée then collapses to digest + feed continu only.
  List<FeedThemeSection> _themes = const [];
  List<Content> _feedContinu = const [];
  List<FeedCarouselData> _feedCarousels = const [];
  bool _feedHasMore = false;
  int _feedPage = 1;
  Map<String, bool> _moreOpen = const {};
  Map<String, bool> _folded = const {};
  bool _closingDismissed = false;
  final Set<String> _dismissedIds = <String>{};

  /// Sections marked as "consumed" during this session via the scroll-past
  /// detection. Persisted to SharedPreferences so they appear as
  /// [FoldedSectionCard] on the next cold launch, but **not** applied to
  /// [state] during this session — so the user never sees the fold happen
  /// while they're scrolling. This is intentional: any in-place size change
  /// of a sliver in a [CustomScrollView] causes a visible content shift, so
  /// we defer the visual fold to the next mount where it's part of the
  /// initial layout (no transition for the user to perceive).
  final Set<String> _persistQueued = <String>{};
  bool _closingPersistQueued = false;

  /// Snapshot of the favorite order we last fetched for. Used by the
  /// userInterestsProvider listener to detect changes and refetch only the
  /// theme sections (cheap) instead of the full tournée.
  List<FavoriteRef> _lastFavorites = const [];

  @override
  Future<FluxContinuState> build() async {
    _digestRepo = ref.read(digestRepositoryProvider);
    _feedRepo = ref.read(feedRepositoryProvider);
    _fluxRepo = ref.read(fluxContinuRepositoryProvider);

    ref.listen<SereinToggleState>(sereinToggleProvider, (prev, next) {
      if (prev?.enabled != next.enabled && state.hasValue) {
        ref.invalidateSelf();
      }
    });

    // React to favorite reorders / additions / removals without rebuilding
    // the digest or feed continuation (those don't depend on favorites).
    ref.listen<AsyncValue<UserInterestsState>>(
      userInterestsProvider,
      (prev, next) {
        final nextFavorites = next.valueOrNull?.favorites;
        if (nextFavorites == null) return;
        if (_favoriteListsEqual(_lastFavorites, nextFavorites)) return;
        if (!state.hasValue) return;
        unawaited(_refetchThemesOnly(nextFavorites));
      },
    );

    return _fetchAll();
  }

  Future<FluxContinuState> _fetchAll() async {
    final isSerene = ref.read(sereinToggleProvider).enabled;

    final results = await Future.wait([
      _safe<DualDigestResponse>(
        () => _digestRepo.fetchBothDigests(),
        'fetchBothDigests',
      ),
      _safe<List<TopTheme>>(
        () => _fluxRepo.getTopThemes(),
        'getTopThemes',
        fallback: const <TopTheme>[],
      ),
      _safe<FeedResponse>(
        () => _feedRepo.getFeed(page: 1, limit: 20, serein: isSerene),
        'getFeed (continuation)',
      ),
    ]);
    final dual = results[0] as DualDigestResponse?;
    final topThemes = (results[1] as List<TopTheme>?) ?? const <TopTheme>[];
    final feed = results[2] as FeedResponse?;

    _essentiel = _buildDigestSection(
      digest: dual?.normal,
      kind: SectionKind.essentiel,
      label: "L'Essentiel du jour",
      blurb: _kEssentielBlurb,
      accent: _kEssentielAccent,
      illustration: _kEssentielIllustration,
      coreVisibleCount: isSerene ? 2 : 4,
    );
    _bonnes = _buildDigestSection(
      digest: dual?.serein,
      kind: SectionKind.bonnes,
      label: 'Bonnes Nouvelles',
      blurb: _kBonnesBlurb,
      accent: _kBonnesAccent,
      illustration: _kBonnesIllustration,
      coreVisibleCount: isSerene ? 4 : 2,
    );

    final favorites = _pickFavorites(topThemes);
    _lastFavorites = favorites;
    _themes = await _fetchThemeSections(favorites, isSerene);

    _feedContinu = feed?.items ?? const [];
    _feedCarousels = feed?.carousels ?? const [];
    _feedHasMore = feed?.pagination.hasNext ?? false;
    _feedPage = 1;
    _moreOpen = const {};
    _folded = await _loadFoldedForToday();
    _closingDismissed = await _loadClosingDismissedForToday();
    unawaited(_purgeOldPrefsKeys());

    return _compose(isSerene);
  }

  FluxContinuState _compose(bool isSerene) {
    final ordered = <FluxSection>[];
    if (isSerene) {
      if (_bonnes != null) ordered.add(_bonnes!);
      ordered.addAll(_themes);
      if (_essentiel != null) ordered.add(_essentiel!);
    } else {
      if (_essentiel != null) ordered.add(_essentiel!);
      ordered.addAll(_themes);
      if (_bonnes != null) ordered.add(_bonnes!);
    }

    // Drop folded/moreOpen entries pointing at sections that didn't survive
    // composition (e.g. a favorite was removed since the prefs were written
    // earlier today). Keeps the maps tight and avoids stale ghosts.
    final keysPresent = ordered.map(sectionKey).toSet();
    final foldedFiltered = <String, bool>{
      for (final entry in _folded.entries)
        if (entry.value && keysPresent.contains(entry.key)) entry.key: true,
    };
    if (foldedFiltered.length != _folded.length) {
      _folded = foldedFiltered;
    }
    final moreOpenFiltered = <String, bool>{
      for (final entry in _moreOpen.entries)
        if (entry.value && keysPresent.contains(entry.key)) entry.key: true,
    };
    if (moreOpenFiltered.length != _moreOpen.length) {
      _moreOpen = moreOpenFiltered;
    }

    return FluxContinuState(
      sections: _filterSections(ordered),
      feedContinu: _filterFeed(_dedupFeed(_feedContinu, ordered)),
      feedCarousels: _feedCarousels,
      isSerene: isSerene,
      moreOpen: _moreOpen,
      folded: _folded,
      closingDismissed: _closingDismissed,
      dismissedIds: Set.unmodifiable(_dismissedIds),
      isLoading: false,
    );
  }

  /// Fires the backend "hide" API for the article without touching local
  /// state. Used the moment the user swipes a card: the card position is
  /// momentarily kept (replaced by an inline feedback banner managed by the
  /// screen), so we don't want the provider to purge the article yet.
  Future<void> markHiddenRemote(String contentId) async {
    if (contentId.isEmpty) return;
    try {
      await _feedRepo.hideContent(contentId);
    } catch (e) {
      debugPrint('FluxContinu: markHiddenRemote failed for $contentId: $e');
    }
  }

  /// Purges the article from the local state — adds the id to the dismissed
  /// set and re-emits filtered sections + feed. No API call (the hide was
  /// already fired via [markHiddenRemote] at swipe time). Called when the
  /// user resolves the inline feedback (chip / close / viewport-exit).
  void confirmDismiss(String contentId) {
    if (contentId.isEmpty) return;
    if (_dismissedIds.contains(contentId)) return;
    _dismissedIds.add(contentId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(
      sections: _filterSections(current.sections),
      feedContinu: _filterFeed(current.feedContinu),
      dismissedIds: Set.unmodifiable(_dismissedIds),
    ));
  }

  /// Restores an article that was hidden remotely but not yet purged from
  /// local state (i.e. the user tapped "Annuler" on the inline feedback).
  /// Fire-and-forget — the article is still in [state], so the card will
  /// reappear in place as soon as the screen clears its pending entry.
  Future<void> undoHide(String contentId) async {
    if (contentId.isEmpty) return;
    try {
      await _feedRepo.unhideContent(contentId);
    } catch (e) {
      debugPrint('FluxContinu: undoHide failed for $contentId: $e');
    }
  }

  /// Backwards-compatible facade for the "no feedback" swipe path: fires the
  /// hide API and purges from state in one go. Retained so call-sites that
  /// don't need the inline feedback flow keep working.
  Future<void> dismissArticle(String contentId) async {
    confirmDismiss(contentId);
    await markHiddenRemote(contentId);
  }

  List<FluxSection> _filterSections(List<FluxSection> sections) {
    if (_dismissedIds.isEmpty) return sections;
    return [
      for (final s in sections)
        switch (s) {
          DigestTopicSection(:final topics) => DigestTopicSection(
              kind: s.kind,
              label: s.label,
              accent: s.accent,
              coreVisibleCount: s.coreVisibleCount,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
              topics: topics
                  .where((t) =>
                      !_dismissedIds.contains(pickTopicLead(t).contentId))
                  .toList(growable: false),
            ),
          FeedThemeSection(
            :final items,
            :final themeSlug,
            :final customTopicId,
          ) =>
            FeedThemeSection(
              kind: s.kind,
              label: s.label,
              accent: s.accent,
              coreVisibleCount: s.coreVisibleCount,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
              themeSlug: themeSlug,
              customTopicId: customTopicId,
              items: items
                  .where((c) => !_dismissedIds.contains(c.id))
                  .toList(growable: false),
            ),
        },
    ];
  }

  List<Content> _filterFeed(List<Content> feed) {
    if (_dismissedIds.isEmpty) return feed;
    return feed.where((c) => !_dismissedIds.contains(c.id)).toList();
  }

  /// Toggle the expand/collapse state of a section's "Plus de…" overflow.
  void toggleMore(FluxSection section) {
    final current = state.valueOrNull;
    if (current == null) return;
    final key = sectionKey(section);
    final next = Map<String, bool>.from(_moreOpen);
    next[key] = !(next[key] ?? false);
    _moreOpen = next;
    state = AsyncData(current.copyWith(moreOpen: next));
  }

  /// Records that the user has scrolled past [section] in this session, **but
  /// does not collapse it on screen**. The section will appear as a
  /// [FoldedSectionCard] on the next cold launch. This avoids the visible
  /// content shift that an in-session resize of a sliver would cause.
  /// Idempotent both per-section and per-session.
  Future<void> markScrolledPastForNextSession(FluxSection section) async {
    final key = sectionKey(section);
    if (_persistQueued.contains(key)) return;
    if (_folded[key] == true) return;
    _persistQueued.add(key);
    final combined = <String, bool>{
      ..._folded,
      for (final k in _persistQueued) k: true,
    };
    await _persistFolded(combined);
  }

  /// Dismisses the closing card "Vous êtes à jour" for the day. Triggered
  /// by the Continuer/Refermer CTAs. Idempotent.
  Future<void> markClosingDismissed() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.closingDismissed) return;
    _closingDismissed = true;
    state = AsyncData(current.copyWith(closingDismissed: true));
    await _persistClosingDismissed(true);
  }

  /// Records the closing-card dismissal for the next session without
  /// hiding it now — same rationale as [markScrolledPastForNextSession].
  Future<void> markClosingDismissedForNextSession() async {
    if (_closingPersistQueued || _closingDismissed) return;
    _closingPersistQueued = true;
    await _persistClosingDismissed(true);
  }

  /// Promotes every section currently in [_persistQueued] to the live
  /// `folded` state. Called only at moments where the editorial slivers
  /// are above the viewport (return from an Explorer article, scroll-to-top
  /// button) so the resulting resize is invisible to the user. Idempotent.
  ///
  /// [exceptKeys] lets the caller skip specific section keys — typically the
  /// section the user just read an article from, which must stay expanded on
  /// return per the "fold only when leaving the section" rule. Excluded keys
  /// remain in [_persistQueued] (and in SharedPreferences) so they will be
  /// folded on the next cold launch — the section is considered consumed for
  /// tomorrow's tournée even though we keep it visible right now.
  void applyPendingFoldsToState({Set<String> exceptKeys = const {}}) {
    if (_persistQueued.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final toPromote = _persistQueued.difference(exceptKeys);
    if (toPromote.isEmpty) return;
    final next = <String, bool>{
      ..._folded,
      for (final k in toPromote) k: true,
    };
    if (next.length == _folded.length &&
        next.entries.every((e) => _folded[e.key] == e.value)) {
      return;
    }
    _folded = next;
    state = AsyncData(current.copyWith(folded: next));
  }

  /// Read-only snapshot of the sections queued for fold at next apply.
  /// Used by the screen to compute the height delta of slivers that are
  /// about to resize, so it can compensate the scroll offset.
  Set<String> persistQueuedSnapshot() => Set.unmodifiable(_persistQueued);

  /// Re-expands a folded section in the current session only (not persisted).
  /// Lets the user re-read a section they previously scrolled past without
  /// disabling the auto-fold for tomorrow's tournée.
  void unfoldLocally(FluxSection section) {
    final current = state.valueOrNull;
    if (current == null) return;
    final key = sectionKey(section);
    if (current.folded[key] != true) return;
    final next = Map<String, bool>.from(current.folded)..remove(key);
    _folded = next;
    state = AsyncData(current.copyWith(folded: next));
  }

  /// Manually folds a section in the current session only (not persisted).
  /// Symmetric of [unfoldLocally] — drives the caret tap on [SectionBanner].
  void foldLocally(FluxSection section) {
    final current = state.valueOrNull;
    if (current == null) return;
    final key = sectionKey(section);
    if (current.folded[key] == true) return;
    final next = Map<String, bool>.from(current.folded)..[key] = true;
    _folded = next;
    state = AsyncData(current.copyWith(folded: next));
  }

  Future<Map<String, bool>> _loadFoldedForToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(_foldedPrefsKey(DateTime.now())) ??
          const <String>[];
      if (names.isEmpty) return const {};
      // Parse tolerantly: legacy enum-style names (`essentiel`, `bonnes`) are
      // still valid. Anything that doesn't match the new string-key shape
      // (`essentiel` / `bonnes` / `theme:slug` / `topic:uuid`) — notably the
      // dead `theme1` / `theme2` from the previous schema — is silently
      // dropped. The day purge below will remove the prefs blob in <24h.
      return {
        for (final name in names)
          if (_isLiveFoldedKey(name)) name: true,
      };
    } catch (e) {
      debugPrint('FluxContinu: _loadFoldedForToday failed: $e');
      return const {};
    }
  }

  Future<void> _persistFolded(Map<String, bool> folded) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names =
          folded.entries.where((e) => e.value).map((e) => e.key).toList();
      await prefs.setStringList(_foldedPrefsKey(DateTime.now()), names);
    } catch (e) {
      debugPrint('FluxContinu: _persistFolded failed: $e');
    }
  }

  Future<bool> _loadClosingDismissedForToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_closingPrefsKey(DateTime.now())) ?? false;
    } catch (e) {
      debugPrint('FluxContinu: _loadClosingDismissedForToday failed: $e');
      return false;
    }
  }

  Future<void> _persistClosingDismissed(bool dismissed) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_closingPrefsKey(DateTime.now()), dismissed);
    } catch (e) {
      debugPrint('FluxContinu: _persistClosingDismissed failed: $e');
    }
  }

  Future<void> _purgeOldPrefsKeys() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final today = DateTime.now();
      final foldedToday = _foldedPrefsKey(today);
      final closingToday = _closingPrefsKey(today);
      final stale = prefs.getKeys().where((k) {
        if (k.startsWith(_kFoldedPrefsKeyPrefix) && k != foldedToday) {
          return true;
        }
        if (k.startsWith(_kClosingPrefsKeyPrefix) && k != closingToday) {
          return true;
        }
        return false;
      }).toList();
      await Future.wait(stale.map(prefs.remove));
    } catch (e) {
      debugPrint('FluxContinu: _purgeOldPrefsKeys failed: $e');
    }
  }

  /// Pull-to-refresh: refetch all upstream calls from scratch.
  ///
  /// Crucially we do NOT bounce through [AsyncLoading] — doing so would
  /// tear down the [RefreshIndicator] mid-pull (the screen renders the
  /// loading skeleton in place of the scroll view), making the gesture
  /// feel broken. Keeping the previous data mounted lets the native
  /// indicator stay visible until the refetch resolves.
  Future<void> refresh() async {
    final next = await AsyncValue.guard(_fetchAll);
    state = next;
  }

  /// Append the next page of the feed continuation.
  Future<void> loadMoreFeed() async {
    if (!_feedHasMore) return;
    final current = state.valueOrNull;
    if (current == null) return;

    final isSerene = ref.read(sereinToggleProvider).enabled;
    final next = _feedPage + 1;
    final page = await _safe<FeedResponse>(
      () => _feedRepo.getFeed(page: next, limit: 20, serein: isSerene),
      'getFeed page=$next',
    );
    if (page == null) return;

    _feedPage = next;
    _feedHasMore = page.pagination.hasNext;
    _feedContinu = [..._feedContinu, ...page.items];
    state = AsyncData(current.copyWith(
      feedContinu: _dedupFeed(_feedContinu, current.sections),
    ));
  }

  FluxSection? _buildDigestSection({
    required DigestResponse? digest,
    required SectionKind kind,
    required String label,
    required String blurb,
    required Color accent,
    required String illustration,
    required int coreVisibleCount,
  }) {
    final topics = digest?.topics
            .where((t) => t.articles.isNotEmpty)
            .toList(growable: false) ??
        const <DigestTopic>[];
    if (topics.isEmpty) return null;
    return DigestTopicSection(
      kind: kind,
      label: label,
      blurb: blurb,
      accent: accent,
      illustrationAsset: illustration,
      coreVisibleCount: coreVisibleCount,
      topics: topics,
    );
  }

  /// Builds a FeedThemeSection from a fetched payload. The label/accent come
  /// from the canonical theme visual mapping for Theme favorites; for custom
  /// topic (Sujet) favorites the caller passes the user's topic name.
  FeedThemeSection? _buildThemeSection({
    required FeedResponse? feed,
    required String label,
    required Color accent,
    String? themeSlug,
    String? customTopicId,
  }) {
    final items = feed?.items ?? const <Content>[];
    if (items.length < 2) return null;
    return FeedThemeSection(
      kind: SectionKind.theme,
      label: label,
      blurb: _kThemeBlurb,
      accent: accent,
      illustrationAsset: _kVeilleIllustration,
      coreVisibleCount: 3,
      themeSlug: themeSlug,
      customTopicId: customTopicId,
      items: items,
    );
  }

  /// Resolves the ordered list of favorite refs to render as theme sections.
  ///
  /// Source of truth: `userInterestsProvider.favorites` (the user-declared
  /// favorites, cap = [_kMaxFavoriteSections]). Fallback when the provider
  /// hasn't loaded yet OR returned an empty list: the legacy `top-themes`
  /// endpoint (weight-based) capped to 3 entries, then canonical macro
  /// themes. This guarantees fresh accounts always see a tournée even before
  /// the backfill migration runs.
  List<FavoriteRef> _pickFavorites(List<TopTheme> topFallback) {
    final favorites =
        ref.read(userInterestsProvider).valueOrNull?.favorites ?? const [];
    if (favorites.isNotEmpty) {
      return favorites.take(_kMaxFavoriteSections).toList(growable: false);
    }
    final valid = topFallback
        .where((t) => themeMap.containsKey(t.interestSlug))
        .map<FavoriteRef>((t) => ThemeFavoriteRef(slug: t.interestSlug))
        .toList();
    if (valid.length >= _kMaxFavoriteSections) {
      return valid.take(_kMaxFavoriteSections).toList(growable: false);
    }
    // Pad with canonical macro themes the user is missing — order: tech,
    // environment, science (matches the backend backfill list).
    const canonical = [fallbackTheme1, fallbackTheme2, 'science'];
    final present =
        valid.whereType<ThemeFavoriteRef>().map((r) => r.slug).toSet();
    for (final slug in canonical) {
      if (valid.length >= _kMaxFavoriteSections) break;
      if (present.contains(slug)) continue;
      valid.add(ThemeFavoriteRef(slug: slug));
      present.add(slug);
    }
    return valid.take(_kMaxFavoriteSections).toList(growable: false);
  }

  /// Fetches one FeedResponse per favorite ref in parallel and turns them
  /// into FeedThemeSections. Drops sections that have fewer than 2 items
  /// (mirrors the legacy behavior — keeps the tournée useful, never sparse).
  Future<List<FeedThemeSection>> _fetchThemeSections(
    List<FavoriteRef> favorites,
    bool isSerene,
  ) async {
    if (favorites.isEmpty) return const [];
    final interestsState = ref.read(userInterestsProvider).valueOrNull;
    final feeds = await Future.wait(
      favorites.map((favRef) => _fetchOneTheme(favRef, isSerene)),
    );
    final sections = <FeedThemeSection>[];
    for (var i = 0; i < favorites.length; i++) {
      final favRef = favorites[i];
      final feed = feeds[i];
      final section = switch (favRef) {
        ThemeFavoriteRef(:final slug) => _buildThemeSection(
            feed: feed,
            label: visualFor(slug).label,
            accent: visualFor(slug).accent,
            themeSlug: slug,
          ),
        CustomTopicFavoriteRef(:final id) => _buildThemeSection(
            feed: feed,
            label: _customTopicLabel(interestsState, id),
            accent: _customTopicAccent(interestsState, id),
            customTopicId: id,
          ),
      };
      if (section != null) sections.add(section);
    }
    return sections;
  }

  Future<FeedResponse?> _fetchOneTheme(FavoriteRef favRef, bool isSerene) {
    return switch (favRef) {
      ThemeFavoriteRef(:final slug) => _safe<FeedResponse>(
          () => _feedRepo.getFeed(
            page: 1,
            limit: 10,
            theme: slug,
            serein: isSerene,
          ),
          'getFeed?theme=$slug',
        ),
      // Backend `/api/feed` accepts a UUID stringified in the `topic` param
      // (story 22.1) — looked up against `user_topic_profiles` scoped on the
      // current user, so no cross-user leak.
      CustomTopicFavoriteRef(:final id) => _safe<FeedResponse>(
          () => _feedRepo.getFeed(
            page: 1,
            limit: 10,
            topic: id,
            serein: isSerene,
          ),
          'getFeed?topic=$id',
        ),
    };
  }

  String _customTopicLabel(UserInterestsState? interests, String id) {
    final found = interests?.customTopics.where((t) => t.id == id).firstOrNull;
    return found?.topicName ?? 'Sujet personnalisé';
  }

  Color _customTopicAccent(UserInterestsState? interests, String id) {
    final found = interests?.customTopics.where((t) => t.id == id).firstOrNull;
    if (found != null) {
      return visualFor(found.slugParent).accent;
    }
    return visualFor('').accent;
  }

  /// Replays only the theme-section fetches against the new favorite list.
  /// Saves the cost of refetching the digest and feed continuation, which
  /// don't depend on favorites.
  Future<void> _refetchThemesOnly(List<FavoriteRef> nextFavorites) async {
    final isSerene = ref.read(sereinToggleProvider).enabled;
    final capped =
        nextFavorites.take(_kMaxFavoriteSections).toList(growable: false);
    final themes = await _fetchThemeSections(capped, isSerene);
    _lastFavorites = capped;
    _themes = themes;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(_compose(isSerene));
  }

  bool _favoriteListsEqual(List<FavoriteRef> a, List<FavoriteRef> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Validates a string key from the legacy SharedPreferences blob against
  /// the new sectionKey scheme. Accepts `essentiel`, `bonnes`, `theme:*`
  /// and `topic:*`; rejects everything else (notably `theme1` / `theme2`).
  bool _isLiveFoldedKey(String key) {
    if (key == SectionKind.essentiel.name) return true;
    if (key == SectionKind.bonnes.name) return true;
    if (key.startsWith('theme:')) return true;
    if (key.startsWith('topic:')) return true;
    return false;
  }

  /// Builds the set of content_ids already rendered in the sections (digest
  /// leads + feed-theme items) and filters them out of the continuation.
  List<Content> _dedupFeed(List<Content> feed, List<FluxSection> sections) {
    final seen = <String>{};
    for (final section in sections) {
      switch (section) {
        case DigestTopicSection(:final topics):
          for (final topic in topics) {
            if (topic.articles.isEmpty) continue;
            seen.add(pickTopicLead(topic).contentId);
          }
        case FeedThemeSection(:final items):
          for (final item in items) {
            seen.add(item.id);
          }
      }
    }
    return feed.where((c) => !seen.contains(c.id)).toList();
  }

  Future<T?> _safe<T>(
    Future<T?> Function() fn,
    String label, {
    T? fallback,
  }) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('FluxContinu: $label failed: $e');
      return fallback;
    }
  }
}
