import 'package:flutter/material.dart';

import '../models/flux_continu_models.dart';
import 'flux_continu_article_card.dart';
import 'plus_de_button.dart';
import 'section_banner.dart';
import 'section_hairline.dart';

/// Composes one section of the Flux Continu V1.8: banner → cards → "Plus
/// de…" overflow → hairline. State (open/closed for the overflow) is
/// passed in so the provider remains the single source of truth.
///
/// For [DigestTopicSection], the section renders one card per topic, the
/// lead article being picked by [pickTopicLead]. For [FeedThemeSection],
/// one card per feed item.
class SectionBlock extends StatelessWidget {
  final FluxSection section;
  final bool isOpen;
  final VoidCallback onToggleMore;
  final ValueChanged<Object> onTapArticle;
  final String? bannerBlurb;
  final bool showHairline;

  const SectionBlock({
    super.key,
    required this.section,
    required this.isOpen,
    required this.onToggleMore,
    required this.onTapArticle,
    this.bannerBlurb,
    this.showHairline = true,
  });

  @override
  Widget build(BuildContext context) {
    final cards = _buildCards();
    final hiddenCount = section.totalCount - section.coreVisibleCount;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBanner(
          title: section.label,
          accent: section.accent,
          blurb: bannerBlurb,
          illustrationAsset: section.illustrationAsset,
        ),
        ...cards,
        if (section.hasOverflow)
          PlusDeButton(
            sectionLabel: section.label,
            accent: section.accent,
            isOpen: isOpen,
            hiddenCount: hiddenCount > 0 ? hiddenCount : 0,
            onTap: onToggleMore,
          ),
        if (showHairline) const SectionHairline(),
      ],
    );
  }

  List<Widget> _buildCards() {
    final isEssentiel = section.kind == SectionKind.essentiel;
    switch (section) {
      case DigestTopicSection(:final topics, :final coreVisibleCount):
        final visible =
            isOpen ? topics : topics.take(coreVisibleCount).toList();
        return [
          for (final topic in visible)
            FluxContinuArticleCard(
              article: pickTopicLead(topic),
              isEssentiel: isEssentiel,
              pressReviewCount: topic.perspectiveCount,
              perspectiveSources: topic.perspectiveSources,
              onTap: () => onTapArticle(pickTopicLead(topic)),
            ),
        ];
      case FeedThemeSection(:final items, :final coreVisibleCount):
        final visible =
            isOpen ? items : items.take(coreVisibleCount).toList();
        return [
          for (final content in visible)
            FluxContinuArticleCard(
              article: content,
              onTap: () => onTapArticle(content),
            ),
        ];
    }
  }
}
