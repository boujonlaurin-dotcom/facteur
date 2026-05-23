import 'package:flutter/material.dart';

import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';

/// Identifier for the **type** of a Flux Continu V1.8 section.
///
/// Multiplicity (0..N) is no longer encoded here — there's a single `theme`
/// value that can appear several times in the same flux (one per user
/// favorite). Per-section state is keyed by [sectionKey] which combines
/// `kind` with the underlying theme slug or custom topic id.
/// Story 23.2 PR-4 : `veille` ajouté comme 4ème kind. La veille (max 1 par
/// user à V1) est rendue comme une section dédiée de la Tournée du jour avec
/// l'accent visuel `sectionVeille1` et un badge "Ma veille".
enum SectionKind { essentiel, bonnes, theme, veille }

/// Stable identity for a section across rebuilds.
///
/// Used as a key into the `moreOpen` / `folded` maps so per-section UI state
/// survives provider refreshes. For theme sections, the slug or custom topic
/// id discriminates between multiple `kind == theme` instances; system
/// sections collapse to just their kind name. La section veille collapse à
/// `'veille'` (un seul par user à V1).
String sectionKey(FluxSection section) {
  return switch (section) {
    EssentielSection() => section.kind.name,
    DigestTopicSection() => section.kind.name,
    FeedThemeSection(:final kind, :final themeSlug, :final customTopicId) =>
      kind == SectionKind.veille
          ? 'veille'
          : customTopicId != null
              ? 'topic:$customTopicId'
              : 'theme:${themeSlug ?? "unknown"}',
  };
}

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

/// One article inside the v3 "L'Essentiel du jour" hi-fi card.
///
/// Backed by `GET /api/essentiel` (Story 9.1) — 5 transversal articles
/// cross-topic, projected from today's digest. Slot is decided by the rank:
/// `rank=1` is the lead, `2..3` are mediums, `4..5` are lights.
class EssentielArticle {
  final String contentId;
  final String title;
  final String url;
  final String? thumbnailUrl;
  final DateTime publishedAt;
  final String sourceName;
  final String sourceLetter;
  final SectionKind kind;
  final String? theme;
  final String sectionLabel;
  final int perspectiveCount;
  final int rank;
  final bool isRead;
  final bool isSaved;
  final bool isLiked;
  final bool isDismissed;

  const EssentielArticle({
    required this.contentId,
    required this.title,
    required this.url,
    required this.publishedAt,
    required this.sourceName,
    required this.sourceLetter,
    required this.sectionLabel,
    required this.rank,
    this.thumbnailUrl,
    this.kind = SectionKind.theme,
    this.theme,
    this.perspectiveCount = 0,
    this.isRead = false,
    this.isSaved = false,
    this.isLiked = false,
    this.isDismissed = false,
  });
}

/// Section v3 "L'Essentiel du jour" — single hi-fi card with 5 cross-topic
/// articles. Distinct from [DigestTopicSection] which renders one card per
/// digest topic. The card itself is built by `EssentielHiFiCard`; the section
/// shell only carries the data and shares the fold/sticky infrastructure.
class EssentielSection extends FluxSection {
  final List<EssentielArticle> articles;

  const EssentielSection({
    required this.articles,
    super.label = 'L’Essentiel du jour',
    super.accent = const Color(0xFFB0470A),
    super.blurb,
    super.illustrationAsset,
  }) : super(kind: SectionKind.essentiel, coreVisibleCount: 5);

  @override
  int get totalCount => articles.length;
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

/// Section backed by `GET /api/feed?theme=…` OR `GET /api/feed?topic=<uuid>`.
/// One card per [Content] item. `themeSlug` carries the macro-theme slug for
/// the closed Facteur vocabulary; `customTopicId` carries the custom-topic
/// UUID when the favorite is a user-defined Sujet. The two are XOR (one of
/// them is set, never both — sectionKey() relies on this).
class FeedThemeSection extends FluxSection {
  final String? themeSlug;
  final String? customTopicId;
  final List<Content> items;

  /// Last page already fetched and appended into [items]. Starts at 1 (the
  /// initial fetch). Bumped by the provider when "Voir +10" loads more.
  final int currentPage;

  /// Backend has more pages available. When false, the load-more button is
  /// disabled (label becomes "Plus rien à voir").
  final bool hasMore;

  /// Set while a load-more request is in flight. Used by the button to show
  /// the "Chargement…" label and ignore taps.
  final bool isLoadingMore;

  const FeedThemeSection({
    required super.kind,
    required super.label,
    required super.accent,
    required super.coreVisibleCount,
    required this.items,
    this.themeSlug,
    this.customTopicId,
    this.currentPage = 1,
    this.hasMore = true,
    this.isLoadingMore = false,
    super.blurb,
    super.illustrationAsset,
  });

  @override
  int get totalCount => items.length;

  FeedThemeSection copyWith({
    List<Content>? items,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingMore,
  }) {
    return FeedThemeSection(
      kind: kind,
      label: label,
      accent: accent,
      coreVisibleCount: coreVisibleCount,
      items: items ?? this.items,
      themeSlug: themeSlug,
      customTopicId: customTopicId,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      blurb: blurb,
      illustrationAsset: illustrationAsset,
    );
  }
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
  // Per-section UI state keyed by [sectionKey]. String keys (rather than
  // `SectionKind`) so multiple theme sections (one per favorite, 0..3) keep
  // independent state — the legacy enum-keyed maps could not represent that.
  final Map<String, bool> moreOpen;
  // Sections the user has fully scrolled past (rendered as compact title
  // cards). Persisted day-by-day so revisiting later in the day keeps the
  // editorial zone collapsed; reset the next day when fresh content arrives.
  final Map<String, bool> folded;
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
    Map<String, bool>? moreOpen,
    Map<String, bool>? folded,
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

  /// Convenience accessors — caller passes the section itself so the key
  /// derivation stays inside the model. Lets widgets stay agnostic of the
  /// string-key encoding scheme.
  bool isOpen(FluxSection section) => moreOpen[sectionKey(section)] ?? false;
  bool isFolded(FluxSection section) => folded[sectionKey(section)] ?? false;

  /// Slugs of the `FeedThemeSection`s that make up today's tournée — used by
  /// the Explorer filter bar to hide chips for themes the user has already
  /// been served above. Custom-topic-only sections (Sujet favoris) don't
  /// surface here because they don't have a theme slug.
  List<String> get tourneeThemeSlugs => sections
      .whereType<FeedThemeSection>()
      .map((s) => s.themeSlug)
      .whereType<String>()
      .toList(growable: false);
}
