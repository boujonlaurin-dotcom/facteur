import 'package:flutter/material.dart';

import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';

/// Identifier for one of the four sections of the Flux Continu V1.8.
enum SectionKind { essentiel, bonnes, theme1, theme2 }

/// One section of the Flux Continu V1.8 home screen.
///
/// Each section renders the same visual shell (banner + cards + optional
/// "Plus de…" expand + hairline) but the payload differs between sections
/// backed by the editorial digest (one card per topic, lead article picked
/// via [pickTopicLead]) and sections backed by the personalized feed (one
/// card per content item).
sealed class FluxSection {
  final SectionKind kind;
  final String label;
  final String? blurb;
  final Color accent;
  final String? illustrationAsset;
  final int coreVisibleCount;

  const FluxSection({
    required this.kind,
    required this.label,
    required this.accent,
    required this.coreVisibleCount,
    this.blurb,
    this.illustrationAsset,
  });

  /// Number of cards the section would render if fully expanded.
  int get totalCount;

  /// Whether some cards are hidden behind the "Plus de…" expand button.
  bool get hasOverflow => totalCount > coreVisibleCount;
}

/// Section backed by `digest.topics` (Essentiel, Bonnes Nouvelles). One
/// card per topic — the lead article is selected via [pickTopicLead].
class DigestTopicSection extends FluxSection {
  final List<DigestTopic> topics;

  const DigestTopicSection({
    required super.kind,
    required super.label,
    required super.accent,
    required super.coreVisibleCount,
    required this.topics,
    super.blurb,
    super.illustrationAsset,
  });

  @override
  int get totalCount => topics.length;
}

/// Section backed by `GET /api/feed?theme=…` (sections #3 and #4). One
/// card per [Content] item.
class FeedThemeSection extends FluxSection {
  final String? themeSlug;
  final List<Content> items;

  const FeedThemeSection({
    required super.kind,
    required super.label,
    required super.accent,
    required super.coreVisibleCount,
    required this.items,
    this.themeSlug,
    super.blurb,
    super.illustrationAsset,
  });

  @override
  int get totalCount => items.length;
}

/// Picks the lead article for a digest topic.
///
/// Priority — followed-source first (user-affinity bonus), otherwise the
/// first article (the pivot rank=1 the backend used to compute the topic's
/// perspectives and bias distribution). Ported from
/// `digest/widgets/topic_section.dart` to keep visual continuity.
DigestItem pickTopicLead(DigestTopic topic) {
  for (final a in topic.articles) {
    if (a.isFollowedSource) return a;
  }
  return topic.articles.first;
}

/// Snapshot of the Flux Continu screen state.
///
/// `sections` is the **ordered** list to render (already accounting for the
/// serein swap and any missing sections). `feedContinu` is the paginated feed
/// rendered below the closing card; the provider dedupes it against the
/// articles already shown above. `feedCarousels` are the editorial carousels
/// (Plus tard c'est maintenant, Autres angles, Pépites…) returned by the
/// feed API, intercalated at their backend-provided position inside the
/// feedContinu list.
@immutable
class FluxContinuState {
  final List<FluxSection> sections;
  final List<Content> feedContinu;
  final List<FeedCarouselData> feedCarousels;
  final bool isSerene;
  final Map<SectionKind, bool> moreOpen;
  // Sections the user has fully scrolled past (rendered as compact title
  // cards). Persisted day-by-day so revisiting later in the day keeps the
  // editorial zone collapsed; reset the next day when fresh content arrives.
  final Map<SectionKind, bool> folded;
  // Whether the closing card "Vous êtes à jour" has been dismissed for the
  // day — either via the Continuer/Refermer buttons or by scrolling past it.
  // Persisted day-by-day, mirroring [folded].
  final bool closingDismissed;
  // Content ids the user has swipe-dismissed during this session. Cards with
  // ids in this set are filtered out before render so the swipe-away feels
  // instant; the hide API call is fire-and-forget in the provider.
  final Set<String> dismissedIds;
  final bool isLoading;
  final Object? error;

  const FluxContinuState({
    this.sections = const [],
    this.feedContinu = const [],
    this.feedCarousels = const [],
    this.isSerene = false,
    this.moreOpen = const {},
    this.folded = const {},
    this.closingDismissed = false,
    this.dismissedIds = const {},
    this.isLoading = true,
    this.error,
  });

  FluxContinuState copyWith({
    List<FluxSection>? sections,
    List<Content>? feedContinu,
    List<FeedCarouselData>? feedCarousels,
    bool? isSerene,
    Map<SectionKind, bool>? moreOpen,
    Map<SectionKind, bool>? folded,
    bool? closingDismissed,
    Set<String>? dismissedIds,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) {
    return FluxContinuState(
      sections: sections ?? this.sections,
      feedContinu: feedContinu ?? this.feedContinu,
      feedCarousels: feedCarousels ?? this.feedCarousels,
      isSerene: isSerene ?? this.isSerene,
      moreOpen: moreOpen ?? this.moreOpen,
      folded: folded ?? this.folded,
      closingDismissed: closingDismissed ?? this.closingDismissed,
      dismissedIds: dismissedIds ?? this.dismissedIds,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool isOpen(SectionKind kind) => moreOpen[kind] ?? false;
  bool isFolded(SectionKind kind) => folded[kind] ?? false;

  /// Slugs of the two `FeedThemeSection` (Veille #1, Veille #2) that make up
  /// today's tournée — used by the Explorer filter bar to hide chips for
  /// themes the user has already been served above.
  List<String> get tourneeThemeSlugs => sections
      .whereType<FeedThemeSection>()
      .map((s) => s.themeSlug)
      .whereType<String>()
      .toList(growable: false);
}
