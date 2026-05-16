import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../digest/models/digest_models.dart';
import '../../digest/models/dual_digest_response.dart';
import '../../digest/providers/digest_provider.dart' show digestRepositoryProvider;
import '../../digest/providers/serein_toggle_provider.dart';
import '../../digest/repositories/digest_repository.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart' show feedRepositoryProvider;
import '../../feed/repositories/feed_repository.dart';
import '../models/flux_continu_models.dart';
import '../repositories/flux_continu_repository.dart';
import '../utils/theme_color_mapping.dart';

/// Accent applied to the Essentiel section banner.
const Color _kEssentielAccent = Color(0xFFB0470A);

/// Accent applied to the Bonnes Nouvelles section banner.
const Color _kBonnesAccent = Color(0xFF2E7D32);

/// Illustration asset associated with each editorial section.
const String _kEssentielIllustration = 'assets/notifications/facteur_avatar.png';
const String _kBonnesIllustration = 'assets/notifications/facteur_goodnews.png';
const String _kVeilleIllustration = 'assets/notifications/facteur_veille.png';

/// Blurbs rendered under each section title.
const String _kEssentielBlurb =
    "Trois lectures denses pour saisir ce qui pèse aujourd'hui — sans tout lire.";
const String _kBonnesBlurb =
    'Des initiatives concrètes, des victoires petites et grandes, pour repartir.';
const String _kThemeBlurb =
    "Les articles récents sur l'un de tes sujets de prédilection — ta veille du jour, sans la chercher.";

/// Prefix for the day-scoped SharedPreferences key that stores which sections
/// the user has already scrolled past today. Keys older than today are purged
/// at startup so a new day starts with every section expanded.
const String _kFoldedPrefsKeyPrefix = 'flux_continu_folded_';
const String _kClosingPrefsKeyPrefix = 'flux_continu_closing_dismissed_';

String _dayKey(DateTime day) => day.toIso8601String().substring(0, 10);

String _foldedPrefsKey(DateTime day) => '$_kFoldedPrefsKeyPrefix${_dayKey(day)}';

String _closingPrefsKey(DateTime day) =>
    '$_kClosingPrefsKeyPrefix${_dayKey(day)}';

SectionKind? _kindByName(String name) {
  for (final k in SectionKind.values) {
    if (k.name == name) return k;
  }
  return null;
}

/// Riverpod provider for the Flux Continu V1.8 home screen.
///
/// Orchestrates three parallel API calls at mount, then two themed feed calls
/// once top-themes have been resolved. Holds an ordered list of sections
/// (already accounting for the serein swap) and a deduped feed continuation
/// to render below the closing card.
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
  FluxSection? _theme1;
  FluxSection? _theme2;
  List<Content> _feedContinu = const [];
  List<FeedCarouselData> _feedCarousels = const [];
  bool _feedHasMore = false;
  int _feedPage = 1;
  Map<SectionKind, bool> _moreOpen = const {};
  Map<SectionKind, bool> _folded = const {};
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
  final Set<SectionKind> _persistQueued = <SectionKind>{};
  bool _closingPersistQueued = false;

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

    final picked = _pickThemes(topThemes);
    final themeResults = await Future.wait(picked.map(
      (slug) => _safe<FeedResponse>(
        () => _feedRepo.getFeed(
          page: 1,
          limit: 10,
          theme: slug,
          serein: isSerene,
        ),
        'getFeed?theme=$slug',
      ),
    ));

    _theme1 = picked.isNotEmpty
        ? _buildThemeSection(picked[0], themeResults[0], SectionKind.theme1)
        : null;
    _theme2 = picked.length >= 2
        ? _buildThemeSection(picked[1], themeResults[1], SectionKind.theme2)
        : null;

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
      if (_theme1 != null) ordered.add(_theme1!);
      if (_theme2 != null) ordered.add(_theme2!);
      if (_essentiel != null) ordered.add(_essentiel!);
    } else {
      if (_essentiel != null) ordered.add(_essentiel!);
      if (_theme1 != null) ordered.add(_theme1!);
      if (_theme2 != null) ordered.add(_theme2!);
      if (_bonnes != null) ordered.add(_bonnes!);
    }

    // Drop folded entries for sections that didn't survive composition
    // (e.g. an empty Bonnes section yesterday won't exist today).
    final kindsPresent = ordered.map((s) => s.kind).toSet();
    final foldedFiltered = <SectionKind, bool>{
      for (final entry in _folded.entries)
        if (entry.value && kindsPresent.contains(entry.key)) entry.key: true,
    };
    if (foldedFiltered.length != _folded.length) {
      _folded = foldedFiltered;
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
                  .where((t) => !_dismissedIds.contains(pickTopicLead(t).contentId))
                  .toList(growable: false),
            ),
          FeedThemeSection(:final items, :final themeSlug) => FeedThemeSection(
              kind: s.kind,
              label: s.label,
              accent: s.accent,
              coreVisibleCount: s.coreVisibleCount,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
              themeSlug: themeSlug,
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
  void toggleMore(SectionKind kind) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = Map<SectionKind, bool>.from(_moreOpen);
    next[kind] = !(next[kind] ?? false);
    _moreOpen = next;
    state = AsyncData(current.copyWith(moreOpen: next));
  }

  /// Records that the user has scrolled past [kind] in this session, **but
  /// does not collapse it on screen**. The section will appear as a
  /// [FoldedSectionCard] on the next cold launch. This avoids the visible
  /// content shift that an in-session resize of a sliver would cause.
  /// Idempotent both per-kind and per-session.
  Future<void> markScrolledPastForNextSession(SectionKind kind) async {
    if (_persistQueued.contains(kind)) return;
    if (_folded[kind] == true) return;
    _persistQueued.add(kind);
    final combined = <SectionKind, bool>{
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
  void applyPendingFoldsToState() {
    if (_persistQueued.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final next = <SectionKind, bool>{
      ..._folded,
      for (final k in _persistQueued) k: true,
    };
    if (next.length == _folded.length &&
        next.entries.every((e) => _folded[e.key] == e.value)) {
      return;
    }
    _folded = next;
    state = AsyncData(current.copyWith(folded: next));
  }

  /// Re-expands a folded section in the current session only (not persisted).
  /// Lets the user re-read a section they previously scrolled past without
  /// disabling the auto-fold for tomorrow's tournée.
  void unfoldLocally(SectionKind kind) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.folded[kind] != true) return;
    final next = Map<SectionKind, bool>.from(current.folded)..remove(kind);
    _folded = next;
    state = AsyncData(current.copyWith(folded: next));
  }

  /// Manually folds a section in the current session only (not persisted).
  /// Symmetric of [unfoldLocally] — drives the caret tap on [SectionBanner].
  void foldLocally(SectionKind kind) {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.folded[kind] == true) return;
    final next = Map<SectionKind, bool>.from(current.folded)..[kind] = true;
    _folded = next;
    state = AsyncData(current.copyWith(folded: next));
  }

  Future<Map<SectionKind, bool>> _loadFoldedForToday() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = prefs.getStringList(_foldedPrefsKey(DateTime.now())) ??
          const <String>[];
      if (names.isEmpty) return const {};
      return {
        for (final name in names)
          if (_kindByName(name) case final k?) k: true,
      };
    } catch (e) {
      debugPrint('FluxContinu: _loadFoldedForToday failed: $e');
      return const {};
    }
  }

  Future<void> _persistFolded(Map<SectionKind, bool> folded) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final names = folded.entries
          .where((e) => e.value)
          .map((e) => e.key.name)
          .toList();
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

  FluxSection? _buildThemeSection(
    String slug,
    FeedResponse? feed,
    SectionKind kind,
  ) {
    final items = feed?.items ?? const <Content>[];
    if (items.length < 2) return null;
    final visual = visualFor(slug);
    return FeedThemeSection(
      kind: kind,
      label: visual.label,
      blurb: _kThemeBlurb,
      accent: visual.accent,
      illustrationAsset: _kVeilleIllustration,
      coreVisibleCount: 3,
      themeSlug: slug,
      items: items,
    );
  }

  List<String> _pickThemes(List<TopTheme> top) {
    final valid = top
        .where((t) => themeMap.containsKey(t.interestSlug))
        .map((t) => t.interestSlug)
        .toList();
    if (valid.length >= 2) return valid.take(2).toList();
    if (valid.length == 1) {
      final fallback =
          valid.first == fallbackTheme1 ? fallbackTheme2 : fallbackTheme1;
      return [valid.first, fallback];
    }
    return [fallbackTheme1, fallbackTheme2];
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
