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
  bool _feedHasMore = false;
  int _feedPage = 1;
  Map<SectionKind, bool> _moreOpen = const {};

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

    _essentiel = _buildDigestSection(
      digest: dual?.normal,
      kind: SectionKind.essentiel,
      label: "L'Essentiel du jour",
      blurb: _kEssentielBlurb,
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
      coreVisibleCount: 2,
    );

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
        ? _buildThemeSection(picked[0], themeResults[0], SectionKind.theme1)
        : null;
    _theme2 = picked.length >= 2
        ? _buildThemeSection(picked[1], themeResults[1], SectionKind.theme2)
        : null;

    _feedContinu = feed?.items ?? const [];
    _feedHasMore = feed?.pagination.hasNext ?? false;
    _feedPage = 1;
    _moreOpen = const {};

    return _compose(isSerene);
  }

  FluxContinuState _compose(bool isSerene) {
    final ordered = <FluxSection>[];
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

  /// Append the next page of the feed continuation.
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
      coreVisibleCount: 2,
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
