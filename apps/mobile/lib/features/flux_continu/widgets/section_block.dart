import 'package:flutter/material.dart';

import '../../feed/widgets/feedback_inline.dart';
import '../models/flux_continu_models.dart';
import 'flux_continu_article_card.dart';
import 'folded_section_card.dart';
import 'plus_de_button.dart';
import 'section_banner.dart';

/// Identifies which chip the user picked on a [FeedbackInline] banner.
enum FluxFeedbackChip { source, topic, alreadySeen }

/// Composes one section of the Flux Continu V1.8: banner → cards → "Plus
/// de…" overflow. State (open/closed for the overflow) is passed in so the
/// provider remains the single source of truth.
///
/// For [DigestTopicSection], the section renders one card per topic, the
/// lead article being picked by [pickTopicLead]. For [FeedThemeSection],
/// one card per feed item.
class SectionBlock extends StatelessWidget {
  final FluxSection section;
  final bool isOpen;
  final bool isFolded;
  final VoidCallback onToggleMore;
  final VoidCallback? onUnfold;
  final VoidCallback? onFold;
  final void Function(Object article, FluxSection section) onTapArticle;
  final ValueChanged<String>? onDismissArticle;

  /// Append the next page of articles to a [FeedThemeSection]. Wired by the
  /// flux_continu screen to `provider.loadMoreTheme(sectionKey)`. Ignored
  /// for [DigestTopicSection] which keeps its legacy fold/expand button.
  final VoidCallback? onLoadMore;

  /// IDs of articles currently in the inline-feedback pending state. When
  /// non-empty, the matching cards are swapped for a [FeedbackInline] at the
  /// same position.
  final Set<String> pendingFeedbackIds;
  final void Function(String contentId, FluxFeedbackChip chip)?
      onSelectFeedbackChip;
  final ValueChanged<String>? onResolveFeedback;
  final ValueChanged<String>? onUndoFeedback;

  /// When true, the section's first article plays the one-shot swipe-left
  /// hint animation. Only the first section on screen should set this.
  final bool enableSwipeHintOnFirstCard;
  final VoidCallback? onSwipeHintComplete;

  /// Optional — when set, the banner renders a small "favorite" star at the
  /// end of its title. Only wired for user-favorite sections (theme/topic);
  /// null on system sections (`essentiel` / `bonnes`).
  final VoidCallback? onTapFavorite;

  const SectionBlock({
    super.key,
    required this.section,
    required this.isOpen,
    required this.onToggleMore,
    required this.onTapArticle,
    this.isFolded = false,
    this.onUnfold,
    this.onFold,
    this.onDismissArticle,
    this.pendingFeedbackIds = const <String>{},
    this.onSelectFeedbackChip,
    this.onResolveFeedback,
    this.onUndoFeedback,
    this.enableSwipeHintOnFirstCard = false,
    this.onSwipeHintComplete,
    this.onTapFavorite,
    this.onLoadMore,
  });

  @override
  Widget build(BuildContext context) {
    // Instant swap (no AnimatedSize): the screen's scroll listener compensates
    // the offset by the exact pixel delta the moment we shrink, so the
    // viewport visually doesn't move. An animated transition here would defeat
    // the compensation by leaving the height in flux when the post-frame
    // callback measures it.
    //
    // [FeedThemeSection] never folds: it uses the in-place "Voir +10"
    // pagination, so the fold UX of digest sections would conflict with
    // that affordance. Only digest sections (essentiel / bonnes) fold.
    final bool canFold = section is DigestTopicSection;
    return (isFolded && canFold) ? _buildFolded() : _buildExpanded();
  }

  Widget _buildFolded() {
    return FoldedSectionCard(
      title: section.label,
      articleCount: section.totalCount,
      onTap: onUnfold,
    );
  }

  Widget _buildExpanded() {
    final cards = _buildCards();
    final section = this.section;
    final hiddenCount = section.totalCount - section.coreVisibleCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBanner(
          title: section.label,
          accent: section.accent,
          blurb: section.blurb,
          illustrationAsset: section.illustrationAsset,
          onTapFold: section is DigestTopicSection ? onFold : null,
          onTapFavorite: onTapFavorite,
        ),
        ...cards,
        if (section is FeedThemeSection)
          LoadMoreButton(
            sectionLabel: section.label,
            hasMore: section.hasMore,
            isLoadingMore: section.isLoadingMore,
            onTap: onLoadMore ?? () {},
          )
        else if (section.hasOverflow)
          PlusDeButton(
            sectionLabel: section.label,
            isOpen: isOpen,
            hiddenCount: hiddenCount > 0 ? hiddenCount : 0,
            onTap: onToggleMore,
          ),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _feedbackInlineFor(String contentId) {
    return Padding(
      key: ValueKey('flux_feedback_$contentId'),
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: FeedbackInline(
        onSelectSource: () =>
            onSelectFeedbackChip?.call(contentId, FluxFeedbackChip.source),
        onSelectTopic: () =>
            onSelectFeedbackChip?.call(contentId, FluxFeedbackChip.topic),
        onSelectAlreadySeen: () =>
            onSelectFeedbackChip?.call(contentId, FluxFeedbackChip.alreadySeen),
        onUndo: () => onUndoFeedback?.call(contentId),
        onClose: () => onResolveFeedback?.call(contentId),
      ),
    );
  }

  List<Widget> _buildCards() {
    final isEssentiel = section.kind == SectionKind.essentiel;
    switch (section) {
      case DigestTopicSection(:final topics, :final coreVisibleCount):
        final visible =
            isOpen ? topics : topics.take(coreVisibleCount).toList();
        return [
          for (var i = 0; i < visible.length; i++)
            if (pendingFeedbackIds
                .contains(pickTopicLead(visible[i]).contentId))
              _feedbackInlineFor(pickTopicLead(visible[i]).contentId)
            else
              FluxContinuArticleCard(
                article: pickTopicLead(visible[i]),
                isEssentiel: isEssentiel,
                pressReviewCount: visible[i].perspectiveCount,
                perspectiveSources: visible[i].perspectiveSources,
                onTap: () =>
                    onTapArticle(pickTopicLead(visible[i]), section),
                onSwipeDismiss: onDismissArticle == null
                    ? null
                    : () =>
                        onDismissArticle!(pickTopicLead(visible[i]).contentId),
                enableSwipeHint: enableSwipeHintOnFirstCard && i == 0,
                onSwipeHintComplete:
                    enableSwipeHintOnFirstCard && i == 0
                        ? onSwipeHintComplete
                        : null,
              ),
        ];
      case FeedThemeSection(:final items):
        // FeedThemeSection always renders the full accumulated list; the
        // in-place LoadMoreButton appends +10 items at a time instead of
        // hiding behind a fold/expand toggle.
        final visible = items;
        return [
          for (var i = 0; i < visible.length; i++)
            if (pendingFeedbackIds.contains(visible[i].id))
              _feedbackInlineFor(visible[i].id)
            else
              FluxContinuArticleCard(
                article: visible[i],
                onTap: () => onTapArticle(visible[i], section),
                onSwipeDismiss: onDismissArticle == null
                    ? null
                    : () => onDismissArticle!(visible[i].id),
                enableSwipeHint: enableSwipeHintOnFirstCard && i == 0,
                onSwipeHintComplete:
                    enableSwipeHintOnFirstCard && i == 0
                        ? onSwipeHintComplete
                        : null,
              ),
        ];
    }
  }
}
