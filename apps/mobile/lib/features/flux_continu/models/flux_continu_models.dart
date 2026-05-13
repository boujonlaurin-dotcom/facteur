import 'package:flutter/material.dart';

import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';

/// Identifier for one of the four sections of the Flux Continu V1.8.
enum SectionKind { essentiel, bonnes, theme1, theme2 }

/// Abstraction over the heterogeneous payloads that feed each section.
///
/// - `essentiel`/`bonnes` are sourced from the editorial digest (DigestItem);
/// - `theme1`/`theme2` are sourced from the personalized feed (Content).
///
/// The screen layer renders cards from `articles`, which holds either type
/// behind an `Object` union. Use [articleId] to extract a stable identifier
/// for dedup against the feed continuation underneath the closing card.
@immutable
class Section {
  final SectionKind kind;
  final String label;
  final Color accent;
  final String? themeSlug;
  final List<Object> articles;
  final int coreCount;

  const Section({
    required this.kind,
    required this.label,
    required this.accent,
    required this.articles,
    required this.coreCount,
    this.themeSlug,
  });

  bool get hasOverflow => articles.length > coreCount;

  /// Returns the content_id for either DigestItem or Content; empty string
  /// if the entry is of an unexpected type (defensive).
  static String articleId(Object article) {
    if (article is DigestItem) return article.contentId;
    if (article is Content) return article.id;
    return '';
  }
}

/// Snapshot of the Flux Continu screen state.
///
/// `sections` is the **ordered** list to render (already accounting for the
/// serein swap and any missing sections). `feedContinu` is the paginated feed
/// rendered below the closing card; the provider dedupes it against the
/// articles already shown above.
@immutable
class FluxContinuState {
  final List<Section> sections;
  final List<Content> feedContinu;
  final bool isSerene;
  final Map<SectionKind, bool> moreOpen;
  final bool isLoading;
  final Object? error;

  const FluxContinuState({
    this.sections = const [],
    this.feedContinu = const [],
    this.isSerene = false,
    this.moreOpen = const {},
    this.isLoading = true,
    this.error,
  });

  FluxContinuState copyWith({
    List<Section>? sections,
    List<Content>? feedContinu,
    bool? isSerene,
    Map<SectionKind, bool>? moreOpen,
    bool? isLoading,
    Object? error,
    bool clearError = false,
  }) {
    return FluxContinuState(
      sections: sections ?? this.sections,
      feedContinu: feedContinu ?? this.feedContinu,
      isSerene: isSerene ?? this.isSerene,
      moreOpen: moreOpen ?? this.moreOpen,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }

  bool isOpen(SectionKind kind) => moreOpen[kind] ?? false;
}
