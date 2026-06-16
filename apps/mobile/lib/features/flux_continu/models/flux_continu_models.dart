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
/// PR « Sources dans la Tournée » : `source` ajouté comme 5ème kind — une
/// source favorite rendue comme section premium (hero logo + top-3 classé),
/// réutilisant le payload [FeedThemeSection] (champs `sourceId`/`sourceLogoUrl`).
enum SectionKind { essentiel, bonnes, theme, veille, source }

/// Origine d'une section de la Tournée du jour (Story 22.3).
///
/// `validated` = section **dédiée** (favori épinglé / source Essentiel /
/// veille) — toujours rendue, jamais masquée par l'algo. `suggested` = section
/// « Choisie pour vous » qui remplit un slot restant, issue d'un thème/source
/// que l'utilisateur suit déjà mais n'a pas épinglé. Défaut `validated` →
/// rétro-compat des payloads/sections qui ne portent pas le champ.
enum SectionOrigin { validated, suggested }

/// Une puce de transparence d'une suggestion (miroir de `ScoreContribution`
/// côté backend, cf. `schemas/content.py`). Story 22.3.
class SuggestionContribution {
  final String label;
  final double points;
  final String? pillar;

  const SuggestionContribution({
    required this.label,
    this.points = 0,
    this.pillar,
  });

  factory SuggestionContribution.fromJson(Map<String, dynamic> json) {
    return SuggestionContribution(
      label: (json['label'] as String?) ?? '',
      points: (json['points'] as num?)?.toDouble() ?? 0,
      pillar: json['pillar'] as String?,
    );
  }
}

/// Raison « Pourquoi cette section ? » d'une suggestion (Story 22.3).
///
/// `label` = la contribution dominante (titre de la sheet) ; `breakdown` =
/// 2-3 puces honnêtes construites côté backend depuis les seules composantes
/// réellement présentes (préférence déclarée / lue + N articles + variété).
class SuggestionReason {
  final String label;
  final List<SuggestionContribution> breakdown;

  const SuggestionReason({required this.label, this.breakdown = const []});

  factory SuggestionReason.fromJson(Map<String, dynamic> json) {
    return SuggestionReason(
      label: (json['label'] as String?) ?? '',
      breakdown: ((json['breakdown'] as List?) ?? const [])
          .whereType<Map<String, dynamic>>()
          .map(SuggestionContribution.fromJson)
          .toList(growable: false),
    );
  }
}

/// Stable identity for a section across rebuilds.
///
/// Used as a key for per-section UI/dérivations (ordre tournée, dédup…) so
/// state survives provider refreshes. For theme sections, the slug or custom topic
/// id discriminates between multiple `kind == theme` instances; system
/// sections collapse to just their kind name. La section veille collapse à
/// `'veille'` (un seul par user à V1).
///
/// **Disambiguation Story 9.2 hotfix** : depuis la PR #650, deux sections
/// peuvent porter `kind = SectionKind.essentiel` :
///   - la nouvelle [EssentielSection] (carte hi-fi "L'Essentiel du jour")
///     → mappée sur `'essentiel_v3'` ;
///   - la [DigestTopicSection] legacy renommée "Actus du jour"
///     → garde la clé historique `'essentiel'`.
String sectionKey(FluxSection section) {
  return switch (section) {
    EssentielSection() => 'essentiel_v3',
    DigestTopicSection() => section.kind.name,
    FeedThemeSection(
      :final kind,
      :final themeSlug,
      :final customTopicId,
      :final sourceId,
    ) =>
      kind == SectionKind.source
          ? 'source:${sourceId ?? "unknown"}'
          : kind == SectionKind.veille
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
  // Signaux user-aware servis par /api/essentiel pour rendre la personnalisation
  // et l'Actu du jour visibles côté carte (pastille, badges, avatar accent).
  final bool isFollowedSource;
  final bool isFollowedTopic;
  final bool isActuDuJour;

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
    this.isFollowedSource = false,
    this.isFollowedTopic = false,
    this.isActuDuJour = false,
  });

  factory EssentielArticle.fromJson(Map<String, dynamic> json) {
    final source =
        (json['source'] as Map?)?.cast<String, dynamic>() ?? const {};
    final sourceName = (source['name'] as String?) ?? '';
    return EssentielArticle(
      contentId: (json['content_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      publishedAt:
          DateTime.tryParse(json['published_at'] as String? ?? '') ??
          DateTime.now(),
      sourceName: sourceName,
      sourceLetter: (json['source_letter'] as String?) ?? _initial(sourceName),
      kind: _parseKind(json['kind'] as String?),
      theme: json['theme'] as String?,
      sectionLabel: (json['section_label'] as String?) ?? '',
      perspectiveCount: (json['perspective_count'] as num?)?.toInt() ?? 0,
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      isRead: (json['is_read'] as bool?) ?? false,
      isSaved: (json['is_saved'] as bool?) ?? false,
      isLiked: (json['is_liked'] as bool?) ?? false,
      isDismissed: (json['is_dismissed'] as bool?) ?? false,
      isFollowedSource: (json['is_followed_source'] as bool?) ?? false,
      isFollowedTopic: (json['is_followed_topic'] as bool?) ?? false,
      isActuDuJour: (json['is_actu_du_jour'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'content_id': contentId,
    'title': title,
    'url': url,
    'thumbnail_url': thumbnailUrl,
    'published_at': publishedAt.toIso8601String(),
    'source': {'name': sourceName},
    'source_letter': sourceLetter,
    'kind': kind.name,
    'theme': theme,
    'section_label': sectionLabel,
    'perspective_count': perspectiveCount,
    'rank': rank,
    'is_read': isRead,
    'is_saved': isSaved,
    'is_liked': isLiked,
    'is_dismissed': isDismissed,
    'is_followed_source': isFollowedSource,
    'is_followed_topic': isFollowedTopic,
    'is_actu_du_jour': isActuDuJour,
  };

  static String _initial(String name) {
    for (final ch in name.trim().split('')) {
      if (ch.trim().isNotEmpty) return ch.toUpperCase();
    }
    return '?';
  }

  static SectionKind _parseKind(String? raw) {
    try {
      return SectionKind.values.byName(raw ?? 'theme');
    } catch (_) {
      return SectionKind.theme;
    }
  }
}

/// Section v3 "L'Essentiel du jour" — single hi-fi card with 5 cross-topic
/// articles. Distinct from [DigestTopicSection] which renders one card per
/// digest topic. The card itself is built by `EssentielHiFiCard`; the section
/// shell only carries the data and shares the sticky infrastructure.
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

  /// UUID de la source quand `kind == SectionKind.source` (PR « Sources dans la
  /// Tournée »). XOR avec themeSlug/customTopicId. Sert de clé `sectionKey` et
  /// route le détail vers `/flux-continu/source/:id`.
  final String? sourceId;

  /// Logo de la source (rendu net dans le hero à la place de l'illustration
  /// thème). Porté ici plutôt qu'un `Source` complet pour éviter une dépendance
  /// du modèle au feature `sources`.
  final String? sourceLogoUrl;

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

  /// Story 22.3 — origine de la section. `suggested` ⇒ section « Choisie pour
  /// vous » (badge + « i » explicatif, dismiss/promotion). Défaut `validated`.
  final SectionOrigin origin;

  /// Raison de transparence (non null seulement quand [origin] est `suggested`).
  final SuggestionReason? reason;

  const FeedThemeSection({
    required super.kind,
    required super.label,
    required super.accent,
    required super.coreVisibleCount,
    required this.items,
    this.themeSlug,
    this.customTopicId,
    this.sourceId,
    this.sourceLogoUrl,
    this.currentPage = 1,
    this.hasMore = true,
    this.isLoadingMore = false,
    this.origin = SectionOrigin.validated,
    this.reason,
    super.blurb,
    super.illustrationAsset,
  });

  @override
  int get totalCount => items.length;

  /// Raccourci : la section est une suggestion « Choisie pour vous ».
  bool get isSuggested => origin == SectionOrigin.suggested;

  FeedThemeSection copyWith({
    List<Content>? items,
    int? currentPage,
    bool? hasMore,
    bool? isLoadingMore,
    // Story « cartes ≤ écran » : le compte d'affichage fitté (min(défaut, fit))
    // est porté par la section. Sans ce paramètre, le dédup/`_filterSections`/
    // `loadMoreTheme` (qui recopient via copyWith) réinitialiseraient le compte
    // au défaut à chaque recompose — le piège le plus facile à introduire.
    int? coreVisibleCount,
  }) {
    return FeedThemeSection(
      kind: kind,
      label: label,
      accent: accent,
      coreVisibleCount: coreVisibleCount ?? this.coreVisibleCount,
      items: items ?? this.items,
      themeSlug: themeSlug,
      customTopicId: customTopicId,
      sourceId: sourceId,
      sourceLogoUrl: sourceLogoUrl,
      currentPage: currentPage ?? this.currentPage,
      hasMore: hasMore ?? this.hasMore,
      isLoadingMore: isLoadingMore ?? this.isLoadingMore,
      // Story 22.3 — origin/reason doivent survivre au dédup/filtre/loadMore
      // (même piège que coreVisibleCount ci-dessus) : un copyWith qui les
      // perdrait retirerait le badge « Choisie pour vous » au 1ᵉʳ recompose.
      origin: origin,
      reason: reason,
      blurb: blurb,
      illustrationAsset: illustrationAsset,
    );
  }
}

/// Collects every content id already rendered above the Explorer continuation
/// — digest leads, Essentiel hi-fi articles, theme/topic items. The screen
/// passes this set as a filter when building the Explorer list so an article
/// already shown in the Tournée du jour never reappears below the closing
/// card.
Set<String> renderedContentIds(List<FluxSection> sections) {
  final seen = <String>{};
  for (final section in sections) {
    switch (section) {
      case EssentielSection(:final articles):
        for (final article in articles) {
          seen.add(article.contentId);
        }
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
  return seen;
}

/// Returns the section that follows [currentKey] in [sections] (the ordered
/// Tournée du jour list), ignoring `EssentielSection` (no "Voir + de") and the
/// current section itself. Returns `null` when the current section is the
/// last one — used by the theme/digest detail screens to decide whether to
/// show the "Sujet suivant" CTA or fall back to "Retour à la Tournée".
FluxSection? nextSectionAfter(List<FluxSection> sections, String currentKey) {
  final ordered = sections
      .whereType<FluxSection>()
      .where((s) {
        if (s is EssentielSection) return false;
        return true;
      })
      .toList(growable: false);
  final currentIndex = ordered.indexWhere((s) => sectionKey(s) == currentKey);
  if (currentIndex == -1) return null;
  if (currentIndex + 1 >= ordered.length) return null;
  return ordered[currentIndex + 1];
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
/// serein swap and any missing sections). The Explorer continuation below the
/// closing card is sourced from `feedProvider` directly (and filtered locally
/// against `dismissedIds` + the ids already rendered in `sections`), so the
/// filter chips of the Explorer sticky bar actually drive the list.
@immutable
class FluxContinuState {
  final List<FluxSection> sections;

  /// Absolute insertion index for the standalone Grille sliver inside
  /// [sections], or `null` when La Grille is hidden, unavailable, or below the
  /// visible cap. The Grille is not a [FluxSection].
  final int? grilleSlotIndex;
  final bool isSerene;
  // Whether the closing card "Vous êtes à jour" has been dismissed for the
  // day — either via the Continuer/Refermer buttons or by scrolling past it.
  // Persisted day-by-day.
  final bool closingDismissed;
  // Content ids the user has swipe-dismissed during this session. Cards with
  // ids in this set are filtered out before render so the swipe-away feels
  // instant; the hide API call is fire-and-forget in the provider.
  final Set<String> dismissedIds;
  // Citation du jour — rendue comme clôture éditoriale juste avant
  // ClosingCardV18 ("Fin de tournée"). Déterministe (seed = user_id + date)
  // côté backend, disponible dans les deux modes normal + sérène.
  final QuoteResponse? quote;
  final bool isLoading;
  final Object? error;

  /// True quand l'état n'est qu'un **squelette** : structure de sections
  /// (en-têtes réels dérivés des prefs locales) sans contenu réel encore
  /// chargé. Émis au démarrage matinal (cache d'hier invalidé / cold start)
  /// pour afficher une page fidèle instantanément, jamais du contenu périmé.
  /// Le rendu réel (`_buildContent`) ne s'active que lorsque ce flag est
  /// `false` ; le screen rend un scaffold placeholder tant qu'il est `true`.
  final bool isSkeleton;

  const FluxContinuState({
    this.sections = const [],
    this.grilleSlotIndex,
    this.isSerene = false,
    this.closingDismissed = false,
    this.dismissedIds = const {},
    this.quote,
    this.isLoading = true,
    this.error,
    this.isSkeleton = false,
  });

  FluxContinuState copyWith({
    List<FluxSection>? sections,
    int? grilleSlotIndex,
    bool? isSerene,
    bool? closingDismissed,
    Set<String>? dismissedIds,
    QuoteResponse? quote,
    bool? isLoading,
    Object? error,
    bool clearError = false,
    bool? isSkeleton,
  }) {
    return FluxContinuState(
      sections: sections ?? this.sections,
      grilleSlotIndex: grilleSlotIndex ?? this.grilleSlotIndex,
      isSerene: isSerene ?? this.isSerene,
      closingDismissed: closingDismissed ?? this.closingDismissed,
      dismissedIds: dismissedIds ?? this.dismissedIds,
      quote: quote ?? this.quote,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      isSkeleton: isSkeleton ?? this.isSkeleton,
    );
  }

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
