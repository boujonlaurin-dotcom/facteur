import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../../veille/providers/veille_active_config_provider.dart';
import '../models/flux_continu_models.dart';
import '../repositories/essentiel_repository.dart';
import '../repositories/flux_continu_repository.dart';
import '../services/tournee_progress_service.dart';
import '../utils/theme_color_mapping.dart';

/// Accent applied to the legacy "Actus du jour" digest topic section
/// (DigestTopicSection avec kind=essentiel). Distinct de l'accent
/// `colors.sectionEssentiel` exposé via le thème car ce dernier dépend du
/// BuildContext. Aligné avec `EssentielSection.accent` (carte hi-fi).
const Color _kEssentielAccent = Color(0xFFB0470A);

/// Accent applied to the Bonnes Nouvelles section banner.
const Color _kBonnesAccent = Color(0xFF2E7D32);

/// Accent applied to the Veille section banner — Story 23.2 PR-4.
/// Aligné sur `FacteurColors.sectionVeille1` (light mode). Le rendu dark
/// reste assuré par les FacteurColors via Theme.of(context).
const Color _kVeilleAccent = Color(0xFF2C3E50);

/// Illustration asset associated with each editorial section.
const String _kEssentielIllustration =
    'assets/notifications/facteur_avatar.png';
const String _kBonnesIllustration = 'assets/notifications/facteur_goodnews.png';
const String _kVeilleIllustration = 'assets/notifications/facteur_veille.png';

/// Blurbs rendered under each section title.
const String _kEssentielBlurb =
    "L'essentiel des actus les plus couvertes en France aujourd'hui, en privilégiant tes sources.";
const String _kActusDuJourBlurb =
    'Les actus les plus couvertes du jour en France, regroupées par sujet.';
const String _kBonnesBlurb = 'Un peu de douceur...';

/// Hard cap on the number of favorite theme sections rendered in the tournée.
/// Mirrors `kFavoriteCap = 3` in the my_interests provider — the value is
/// duplicated here only because the maps key by sectionKey and we slice the
/// favorite list during composition. Keep aligned with the backend constant.
const int _kMaxFavoriteSections = 3;

/// Number of items requested per page for each theme section of the Tournée
/// (initial load + each "loadMoreTheme" call). When the backend returns
/// strictly fewer items than this, [_buildThemeSection] forces hasMore=false —
/// no subsequent page can exist regardless of what the backend's
/// pagination.hasNext (computed from a pre-compression candidate count) says.
const int _kThemeSectionPageLimit = 10;

/// Riverpod provider for the Flux Continu V1.8 home screen.
///
/// Orchestrates three parallel API calls at mount (digest, top-themes,
/// essentiel) then up to three themed feed calls once the user's favorites
/// have been resolved. Holds an ordered list of sections (already accounting
/// for the serein swap). The Explorer continuation rendered below the closing
/// card is sourced from `feedProvider` so the filter chips in the Explorer
/// sticky bar actually shape the list.
final fluxContinuProvider =
    AsyncNotifierProvider<FluxContinuNotifier, FluxContinuState>(
      FluxContinuNotifier.new,
    );

class FluxContinuNotifier extends AsyncNotifier<FluxContinuState> {
  late DigestRepository _digestRepo;
  late FeedRepository _feedRepo;
  late FluxContinuRepository _fluxRepo;
  late EssentielRepository _essentielRepo;

  FluxSection? _essentiel;
  // Section "Actus du jour" : DigestTopicSection legacy (kind=essentiel)
  // restaurée après le hotfix Story 9.2 — la nouvelle EssentielSection
  // (carte hi-fi v3) occupe désormais le nom "L'Essentiel du jour" et
  // celle-ci reprend les topics du digest sous le nouveau nom.
  FluxSection? _actusDuJour;
  FluxSection? _bonnes;
  // Up to [_kMaxFavoriteSections] theme/topic sections, ordered to mirror
  // `userInterestsProvider.favorites`. Empty when the user has no favorites
  // — the tournée then collapses to digest only.
  List<FeedThemeSection> _themes = const [];
  Map<String, bool> _moreOpen = const {};
  Map<String, bool> _folded = const {};
  bool _closingDismissed = false;
  // Citation du jour servie par le backend (sérène ou normal — même pool
  // YAML, sélection déterministe seed = user_id + date). Rendue avant
  // ClosingCardV18 comme clôture éditoriale de la tournée.
  QuoteResponse? _quote;
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
    _essentielRepo = ref.read(essentielRepositoryProvider);

    ref.listen<SereinToggleState>(sereinToggleProvider, (prev, next) {
      if (prev?.enabled != next.enabled && state.hasValue) {
        ref.invalidateSelf();
      }
    });

    // React to favorite reorders / additions / removals without rebuilding
    // the digest (the digest doesn't depend on favorites).
    ref.listen<AsyncValue<UserInterestsState>>(userInterestsProvider, (
      prev,
      next,
    ) {
      final nextFavorites = next.valueOrNull?.favorites;
      if (nextFavorites == null) return;
      if (_favoriteListsEqual(_lastFavorites, nextFavorites)) return;
      if (!state.hasValue) return;
      unawaited(_refetchThemesOnly(nextFavorites));
    });

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
      _safe<List<EssentielArticle>>(
        () async => (await _essentielRepo.fetch()) ?? const [],
        'fetchEssentiel',
        fallback: const <EssentielArticle>[],
      ),
    ]);
    final dual = results[0] as DualDigestResponse?;
    final topThemes = (results[1] as List<TopTheme>?) ?? const <TopTheme>[];
    final essentielArticles =
        (results[2] as List<EssentielArticle>?) ?? const <EssentielArticle>[];

    // PR2 — la section "Essentiel" du haut du feed est désormais alimentée
    // par GET /api/essentiel (5 articles transversaux). Si l'endpoint n'a
    // rien servi (preparing/erreur), on ne rend pas la section : le digest
    // legacy reste affiché juste en dessous sous le nom "Actus du jour",
    // et Bonnes Nouvelles n'est pas affectée.
    _essentiel = _buildEssentielSection(essentielArticles);
    // Hotfix Story 9.2 — "Actus du jour" : DigestTopicSection legacy,
    // alimentée par `dual.normal` (digest classique), avec le label
    // historique "Actus du jour" (anciennement "L'Essentiel du jour" avant
    // que la carte hi-fi v3 ne reprenne ce nom).
    _actusDuJour = _buildDigestSection(
      digest: dual?.normal,
      kind: SectionKind.essentiel,
      label: 'Actus du jour',
      blurb: _kActusDuJourBlurb,
      accent: _kEssentielAccent,
      illustration: _kEssentielIllustration,
      coreVisibleCount: 3,
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
    // Citation du jour — même pool dans les deux digests (déterministe par
    // user/date), on prend le sérène par défaut et on retombe sur le normal
    // si seul l'un des deux a réussi.
    _quote = dual?.serein?.quote ?? dual?.normal?.quote;

    final favorites = _pickFavorites(topThemes);
    _lastFavorites = favorites;
    _themes = await _fetchThemeSections(favorites, isSerene);

    _moreOpen = const {};
    _folded = await _loadFoldedForToday();
    _closingDismissed = await _loadClosingDismissedForToday();
    unawaited(_purgeOldPrefsKeys());

    return _compose(isSerene);
  }

  FluxContinuState _compose(bool isSerene) {
    final ordered = <FluxSection>[];
    if (isSerene) {
      // Mode sérène — "L'Essentiel du jour" reste en tête (parité avec le
      // mode normal), puis Bonnes Nouvelles, thèmes favoris, "Actus du jour".
      if (_essentiel != null) ordered.add(_essentiel!);
      if (_bonnes != null) ordered.add(_bonnes!);
      ordered.addAll(_themes);
      if (_actusDuJour != null) ordered.add(_actusDuJour!);
    } else {
      // Mode normal — carte hi-fi v3 ("L'Essentiel du jour"),
      // puis "Actus du jour" (digest legacy regroupé par sujet),
      // puis les thèmes favoris, puis Bonnes Nouvelles.
      if (_essentiel != null) ordered.add(_essentiel!);
      if (_actusDuJour != null) ordered.add(_actusDuJour!);
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

    // Filter persistQueued against present sections to avoid stale keys
    // surviving a compose (e.g. a favorite was removed).
    final persistFiltered = _persistQueued.where(keysPresent.contains).toSet();
    if (persistFiltered.length != _persistQueued.length) {
      _persistQueued
        ..clear()
        ..addAll(persistFiltered);
    }

    return FluxContinuState(
      sections: _filterSections(ordered),
      isSerene: isSerene,
      moreOpen: _moreOpen,
      folded: _folded,
      closingDismissed: _closingDismissed,
      dismissedIds: Set.unmodifiable(_dismissedIds),
      markedForNextSession: Set.unmodifiable(_persistQueued),
      quote: _quote,
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
  /// set and re-emits filtered sections. No API call (the hide was already
  /// fired via [markHiddenRemote] at swipe time). The Explorer continuation
  /// reads its items from `feedProvider`, so the screen layer applies the
  /// same `dismissedIds` filter there. Called when the user resolves the
  /// inline feedback (chip / close / viewport-exit).
  void confirmDismiss(String contentId) {
    if (contentId.isEmpty) return;
    if (_dismissedIds.contains(contentId)) return;
    _dismissedIds.add(contentId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sections: _filterSections(current.sections),
        dismissedIds: Set.unmodifiable(_dismissedIds),
      ),
    );
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
          EssentielSection(:final articles) => EssentielSection(
            articles: articles
                .where((a) => !_dismissedIds.contains(a.contentId))
                .toList(growable: false),
            blurb: s.blurb,
            illustrationAsset: s.illustrationAsset,
          ),
          DigestTopicSection(:final topics) => DigestTopicSection(
            kind: s.kind,
            label: s.label,
            accent: s.accent,
            coreVisibleCount: s.coreVisibleCount,
            blurb: s.blurb,
            illustrationAsset: s.illustrationAsset,
            topics: topics
                .where(
                  (t) => !_dismissedIds.contains(pickTopicLead(t).contentId),
                )
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

  /// Marks a single article as read in-memory (same-session visual feedback).
  ///
  /// Called by [FluxContinuScreen._openArticle] after the reader route pops so
  /// the card immediately shows the grey + check badge without waiting for a
  /// pull-to-refresh. No API call — the reader already fires the status update
  /// independently.
  void markArticleRead(String contentId) {
    if (contentId.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = [
      for (final s in current.sections)
        switch (s) {
          EssentielSection(:final articles) => EssentielSection(
            articles: [
              for (final a in articles)
                if (a.contentId == contentId)
                  EssentielArticle(
                    contentId: a.contentId,
                    title: a.title,
                    url: a.url,
                    thumbnailUrl: a.thumbnailUrl,
                    publishedAt: a.publishedAt,
                    sourceName: a.sourceName,
                    sourceLetter: a.sourceLetter,
                    sectionLabel: a.sectionLabel,
                    rank: a.rank,
                    kind: a.kind,
                    theme: a.theme,
                    perspectiveCount: a.perspectiveCount,
                    isRead: true,
                    isSaved: a.isSaved,
                    isLiked: a.isLiked,
                    isDismissed: a.isDismissed,
                    isFollowedSource: a.isFollowedSource,
                    isFollowedTopic: a.isFollowedTopic,
                    isActuDuJour: a.isActuDuJour,
                  )
                else
                  a,
            ],
            blurb: s.blurb,
            illustrationAsset: s.illustrationAsset,
          ),
          DigestTopicSection(:final topics) => DigestTopicSection(
            kind: s.kind,
            label: s.label,
            accent: s.accent,
            coreVisibleCount: s.coreVisibleCount,
            blurb: s.blurb,
            illustrationAsset: s.illustrationAsset,
            topics: [
              for (final t in topics)
                t.copyWith(
                  articles: [
                    for (final a in t.articles)
                      if (a.contentId == contentId)
                        a.copyWith(isRead: true)
                      else
                        a,
                  ],
                ),
            ],
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
              items: [
                for (final c in items)
                  if (c.id == contentId)
                    c.copyWith(status: ContentStatus.consumed)
                  else
                    c,
              ],
            ),
        },
    ];
    state = AsyncData(current.copyWith(sections: updated));
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

  /// In-place pagination for the Tournée du jour theme sections. Fetches the
  /// next page from `/api/feed?theme=…&personalized=true` (or topic UUID for
  /// custom topics) and appends it to the section's [FeedThemeSection.items]
  /// — same backend curation as the initial load, so users only see articles
  /// from sources they follow, within the last 24h.
  ///
  /// No-op when the section is not in [state.sections], is already loading,
  /// or the backend reported no more pages.
  Future<void> loadMoreTheme(String key) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.sections.indexWhere(
      (s) => s is FeedThemeSection && sectionKey(s) == key,
    );
    if (idx < 0) return;
    final target = current.sections[idx] as FeedThemeSection;
    if (target.isLoadingMore || !target.hasMore) return;

    final loading = target.copyWith(isLoadingMore: true);
    final loadingSections = List<FluxSection>.from(current.sections)
      ..[idx] = loading;
    state = AsyncData(current.copyWith(sections: loadingSections));

    final isSerene = current.isSerene;
    final nextPage = target.currentPage + 1;
    final theme = target.themeSlug;
    final topic = target.customTopicId;
    final response = await _safe<FeedResponse>(
      () => _feedRepo.getFeed(
        page: nextPage,
        limit: _kThemeSectionPageLimit,
        theme: theme,
        topic: topic,
        serein: isSerene,
        personalized: true,
      ),
      'loadMoreTheme($key)',
    );

    // Re-read state in case it shifted while the request was in flight.
    final afterCurrent = state.valueOrNull;
    if (afterCurrent == null) return;
    final afterIdx = afterCurrent.sections.indexWhere(
      (s) => s is FeedThemeSection && sectionKey(s) == key,
    );
    if (afterIdx < 0) return;
    final afterTarget = afterCurrent.sections[afterIdx] as FeedThemeSection;

    final FeedThemeSection updated;
    if (response == null || response.items.isEmpty) {
      // Treat empty/error response as "no more" so the button settles into
      // the disabled "Plus rien à voir" state rather than spinning forever.
      updated = afterTarget.copyWith(isLoadingMore: false, hasMore: false);
    } else {
      // Dedupe by content id — guards against a new article being published
      // between page 1 and page 2 and shifting the chronological cursor.
      final existingIds = {for (final item in afterTarget.items) item.id};
      final appended = [
        ...afterTarget.items,
        for (final item in response.items)
          if (!existingIds.contains(item.id)) item,
      ];
      final hasMore = _themeHasMore(
        response.pagination.hasNext,
        response.items.length,
      );
      updated = afterTarget.copyWith(
        items: appended,
        currentPage: nextPage,
        hasMore: hasMore,
        isLoadingMore: false,
      );
    }
    final nextSections = List<FluxSection>.from(afterCurrent.sections)
      ..[afterIdx] = updated;
    state = AsyncData(afterCurrent.copyWith(sections: nextSections));
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
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          markedForNextSession: Set.unmodifiable(_persistQueued),
        ),
      );
    }
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
    final next = <String, bool>{..._folded, for (final k in toPromote) k: true};
    if (next.length == _folded.length &&
        next.entries.every((e) => _folded[e.key] == e.value)) {
      return;
    }
    _folded = next;
    _persistQueued.removeAll(toPromote);
    state = AsyncData(
      current.copyWith(
        folded: next,
        markedForNextSession: Set.unmodifiable(_persistQueued),
      ),
    );
  }

  /// Read-only snapshot of the sections queued for fold at next apply.
  /// Used by the screen to compute the height delta of slivers that are
  /// about to resize, so it can compensate the scroll offset.
  Set<String> persistQueuedSnapshot() => Set.unmodifiable(_persistQueued);

  /// Re-expands a folded section. Also purges the section from
  /// [_persistQueued] and from the day-scoped SharedPreferences blob so a
  /// cold launch in the same day does not re-fold the section.
  ///
  /// Without the prefs purge, [markScrolledPastForNextSession] would have
  /// persisted the fold immediately and [_loadFoldedForToday] would restore
  /// it on next mount — leaving sections like "Actus du jour" stuck folded
  /// forever once the user has scrolled past them once.
  void unfoldLocally(FluxSection section) {
    final current = state.valueOrNull;
    if (current == null) return;
    final key = sectionKey(section);
    final wasFolded = current.folded[key] == true;
    final wasQueued = _persistQueued.remove(key);
    if (!wasFolded && !wasQueued) return;
    if (wasFolded) {
      final next = Map<String, bool>.from(current.folded)..remove(key);
      _folded = next;
      state = AsyncData(
        current.copyWith(
          folded: next,
          markedForNextSession: Set.unmodifiable(_persistQueued),
        ),
      );
    } else if (wasQueued) {
      state = AsyncData(
        current.copyWith(
          markedForNextSession: Set.unmodifiable(_persistQueued),
        ),
      );
    }
    // Rewrite the prefs blob with the new (live + still-queued) fold set so
    // the unfold survives a cold launch in the same tournée day.
    unawaited(
      _persistFolded({..._folded, for (final k in _persistQueued) k: true}),
    );
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
    // Parse tolerantly: legacy enum-style names (`essentiel`, `bonnes`) are
    // still valid. Anything that doesn't match the new string-key shape
    // (`essentiel` / `bonnes` / `theme:slug` / `topic:uuid`) — notably the
    // dead `theme1` / `theme2` from the previous schema — is silently
    // dropped. The day purge below will remove the prefs blob in <24h.
    return ref
        .read(tourneeProgressServiceProvider)
        .loadFoldedForToday(isLiveKey: _isLiveFoldedKey);
  }

  Future<void> _persistFolded(Map<String, bool> folded) async {
    await ref.read(tourneeProgressServiceProvider).persistFolded(folded);
  }

  Future<bool> _loadClosingDismissedForToday() async {
    return ref
        .read(tourneeProgressServiceProvider)
        .loadClosingDismissedForToday();
  }

  Future<void> _persistClosingDismissed(bool dismissed) async {
    await ref
        .read(tourneeProgressServiceProvider)
        .setClosingDismissedToday(dismissed);
  }

  Future<void> _purgeOldPrefsKeys() async {
    await ref.read(tourneeProgressServiceProvider).purgeOldPrefsKeys();
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

  /// Builds the v3 "L'Essentiel du jour" hi-fi section from the 5 articles
  /// returned by `GET /api/essentiel`. Returns `null` when the endpoint hasn't
  /// produced anything yet (202 preparing or transient failure) so the screen
  /// degrades gracefully — Bonnes Nouvelles + thèmes restent visibles.
  FluxSection? _buildEssentielSection(List<EssentielArticle> articles) {
    if (articles.isEmpty) return null;
    return EssentielSection(
      articles: articles,
      illustrationAsset: _kEssentielIllustration,
      blurb: _kEssentielBlurb,
    );
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
    final topics =
        digest?.topics
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

  /// Returns true when more theme pages exist. Guards against the backend's
  /// total_candidates being computed before compression layers — a partial page
  /// (< limit) is definitive proof that no next page exists regardless of
  /// pagination.hasNext.
  bool _themeHasMore(bool hasNext, int itemCount) =>
      hasNext && itemCount >= _kThemeSectionPageLimit;

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
    final hasMore = _themeHasMore(
      feed?.pagination.hasNext ?? false,
      items.length,
    );
    return FeedThemeSection(
      kind: SectionKind.theme,
      label: label,
      accent: accent,
      illustrationAsset: _kVeilleIllustration,
      coreVisibleCount: 3,
      themeSlug: themeSlug,
      customTopicId: customTopicId,
      items: items,
      hasMore: hasMore,
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
    final present = valid
        .whereType<ThemeFavoriteRef>()
        .map((r) => r.slug)
        .toSet();
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
        // Story 23.2 PR-4 : la veille devient une section Tournée dédiée
        // avec son propre accent et label, calculée séparément des thèmes.
        VeilleFavoriteRef() => _buildVeilleSection(feed),
      };
      if (section != null) sections.add(section);
    }
    return sections;
  }

  Future<FeedResponse?> _fetchOneTheme(FavoriteRef favRef, bool isSerene) {
    // `personalized: true` flips the backend to "followed sources only +
    // 24h window + user_subtopics boost" for the Tournée du jour theme
    // sections (vs. the unrestricted exploration mode used by feed chips).
    return switch (favRef) {
      ThemeFavoriteRef(:final slug) => _safe<FeedResponse>(
        () => _feedRepo.getFeed(
          page: 1,
          limit: _kThemeSectionPageLimit,
          theme: slug,
          serein: isSerene,
          personalized: true,
        ),
        'getFeed?theme=$slug&personalized=true',
      ),
      // Backend `/api/feed` accepts a UUID stringified in the `topic` param
      // (story 22.1) — looked up against `user_topic_profiles` scoped on the
      // current user, so no cross-user leak.
      CustomTopicFavoriteRef(:final id) => _safe<FeedResponse>(
        () => _feedRepo.getFeed(
          page: 1,
          limit: _kThemeSectionPageLimit,
          topic: id,
          serein: isSerene,
          personalized: true,
        ),
        'getFeed?topic=$id&personalized=true',
      ),
      // Story 23.2 PR-4 : la veille est résolue via `/api/veille/feed`,
      // exposée par FluxContinuRepository.getVeilleFeedItems (normalise la
      // réponse en FeedResponse Content-compatible).
      VeilleFavoriteRef() => _safe<FeedResponse>(
        () => ref
            .read(fluxContinuRepositoryProvider)
            .getVeilleFeedItems(limit: 10, serein: isSerene),
        'getVeilleFeedItems',
      ),
    };
  }

  /// Construit la section veille — accent dédié `sectionVeille1` + label
  /// dérivé du `theme_label` de la `VeilleConfig` active (résolu via
  /// `veilleActiveConfigProvider`). Story 23.2 PR-4.
  FeedThemeSection? _buildVeilleSection(FeedResponse? feed) {
    final items = feed?.items ?? const <Content>[];
    if (items.length < 2) return null;
    final activeCfg = ref.read(veilleActiveConfigProvider).valueOrNull;
    final label = activeCfg == null
        ? 'Ma veille'
        : 'Ma veille — ${activeCfg.themeLabel}';
    return FeedThemeSection(
      kind: SectionKind.veille,
      label: label,
      blurb: 'Les derniers articles de ta veille personnalisée.',
      accent: _kVeilleAccent,
      illustrationAsset: _kVeilleIllustration,
      coreVisibleCount: 3,
      items: items,
    );
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
  /// Saves the cost of refetching the digest, which doesn't depend on
  /// favorites.
  Future<void> _refetchThemesOnly(List<FavoriteRef> nextFavorites) async {
    final isSerene = ref.read(sereinToggleProvider).enabled;
    final capped = nextFavorites
        .take(_kMaxFavoriteSections)
        .toList(growable: false);
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
