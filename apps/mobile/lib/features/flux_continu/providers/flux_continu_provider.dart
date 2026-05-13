import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

  Section? _essentiel;
  Section? _bonnes;
  Section? _theme1;
  Section? _theme2;
  List<Content> _feedContinu = const [];
  bool _feedHasMore = false;
  int _feedPage = 1;
  Map<SectionKind, bool> _moreOpen = const {};

  @override
  Future<FluxContinuState> build() async {
    _digestRepo = ref.read(digestRepositoryProvider);
    _feedRepo = ref.read(feedRepositoryProvider);
    _fluxRepo = ref.read(fluxContinuRepositoryProvider);

    // Refetch from scratch when the serein toggle flips so themed feeds and
    // the feed continuation pick up the right filter. The sections #1 and #2
    // swap is applied locally in `_compose`.
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
      _safe<DualDigestResponse?>(
        () => _digestRepo.fetchBothDigests(),
        'fetchBothDigests',
      ),
      _safe<List<TopTheme>>(
        () => _fluxRepo.getTopThemes(),
        'getTopThemes',
        fallback: const <TopTheme>[],
      ),
      _safe<FeedResponse?>(
        () => _feedRepo.getFeed(page: 1, limit: 20, serein: isSerene),
        'getFeed (continuation)',
      ),
    ]);
    final dual = results[0] as DualDigestResponse?;
    final topThemes = (results[1] as List<TopTheme>?) ?? const <TopTheme>[];
    final feed = results[2] as FeedResponse?;

    _essentiel = dual?.normal != null
        ? Section(
            kind: SectionKind.essentiel,
            label: 'Essentiel',
            accent: _kEssentielAccent,
            articles: _flattenDigest(dual!.normal!),
            coreCount: 3,
          )
        : null;
    _bonnes = dual?.serein != null
        ? Section(
            kind: SectionKind.bonnes,
            label: 'Bonnes Nouvelles',
            accent: _kBonnesAccent,
            articles: _flattenDigest(dual!.serein!),
            coreCount: 2,
          )
        : null;

    final picked = _pickThemes(topThemes);
    final themeResults = await Future.wait(picked.map(
      (slug) => _safe<FeedResponse?>(
        () => _feedRepo.getFeed(
          page: 1,
          limit: 5,
          theme: slug,
          serein: isSerene,
        ),
        'getFeed?theme=$slug',
      ),
    ));

    _theme1 = picked.isNotEmpty
        ? _maybeThemeSection(picked[0], themeResults[0], SectionKind.theme1)
        : null;
    _theme2 = picked.length >= 2
        ? _maybeThemeSection(picked[1], themeResults[1], SectionKind.theme2)
        : null;

    _feedContinu = feed?.items ?? const [];
    _feedHasMore = feed?.pagination.hasNext ?? false;
    _feedPage = 1;
    _moreOpen = const {};

    return _compose(isSerene);
  }

  FluxContinuState _compose(bool isSerene) {
    final ordered = <Section>[];
    if (isSerene) {
      if (_bonnes != null) ordered.add(_bonnes!);
      if (_essentiel != null) ordered.add(_essentiel!);
    } else {
      if (_essentiel != null) ordered.add(_essentiel!);
      if (_bonnes != null) ordered.add(_bonnes!);
    }
    if (_theme1 != null) ordered.add(_theme1!);
    if (_theme2 != null) ordered.add(_theme2!);

    return FluxContinuState(
      sections: ordered,
      feedContinu: _dedupFeed(_feedContinu, ordered),
      isSerene: isSerene,
      moreOpen: _moreOpen,
      isLoading: false,
    );
  }

  /// Toggle the expand/collapse state of a section's "Plus de…" overflow.
  /// Updates state synchronously — no network call.
  void toggleMore(SectionKind kind) {
    final current = state.valueOrNull;
    if (current == null) return;
    final next = Map<SectionKind, bool>.from(_moreOpen);
    next[kind] = !(next[kind] ?? false);
    _moreOpen = next;
    state = AsyncData(current.copyWith(moreOpen: next));
  }

  /// Pull-to-refresh: refetch all upstream calls from scratch.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetchAll);
  }

  /// Append the next page of the feed continuation. No-op if a previous load
  /// has signalled there is no more data.
  Future<void> loadMoreFeed() async {
    if (!_feedHasMore) return;
    final current = state.valueOrNull;
    if (current == null) return;

    final isSerene = ref.read(sereinToggleProvider).enabled;
    final next = _feedPage + 1;
    final page = await _safe<FeedResponse?>(
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

  Section? _maybeThemeSection(
    String slug,
    FeedResponse? feed,
    SectionKind kind,
  ) {
    final items = feed?.items ?? const <Content>[];
    if (items.length < 2) return null;
    final visual = visualFor(slug);
    return Section(
      kind: kind,
      label: visual.label,
      accent: visual.accent,
      themeSlug: slug,
      articles: items,
      coreCount: 2,
    );
  }

  List<DigestItem> _flattenDigest(DigestResponse digest) {
    // Both editorial_v1 and topics_v1 populate `items` for backward compat
    // (cf. packages/api/app/schemas/digest.py:242). Cap at 5 so the section
    // shows `coreCount` visible + a small expand area.
    return digest.items.take(5).toList();
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

  List<Content> _dedupFeed(List<Content> feed, List<Section> sections) {
    final seen = <String>{};
    for (final section in sections) {
      for (final article in section.articles) {
        final id = Section.articleId(article);
        if (id.isNotEmpty) seen.add(id);
      }
    }
    return feed.where((c) => !seen.contains(c.id)).toList();
  }

  Future<T> _safe<T>(
    Future<T> Function() fn,
    String label, {
    T? fallback,
  }) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('FluxContinu: $label failed: $e');
      if (fallback != null) return fallback;
      return null as T;
    }
  }
}
