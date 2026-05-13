import 'package:flutter/material.dart';

import '../models/flux_continu_models.dart';
import 'flux_continu_article_card.dart';
import 'plus_de_button.dart';
import 'section_banner.dart';
import 'section_hairline.dart';

/// Composes one section of the Flux Continu V1.8: banner → cards → "Plus
/// de…" overflow → hairline. State (open/closed for the overflow) is
/// passed in so the provider remains the single source of truth.
class SectionBlock extends StatelessWidget {
  final Section section;
  final bool isOpen;
  final VoidCallback onToggleMore;
  final ValueChanged<Object> onTapArticle;
  final String? bannerBlurb;
  final IconData? bannerIcon;
  final bool showHairline;

  const SectionBlock({
    super.key,
    required this.section,
    required this.isOpen,
    required this.onToggleMore,
    required this.onTapArticle,
    this.bannerBlurb,
    this.bannerIcon,
    this.showHairline = true,
  });

  @override
  Widget build(BuildContext context) {
    final visible = isOpen
        ? section.articles
        : section.articles.take(section.coreCount).toList();
    final hiddenCount = section.articles.length - section.coreCount;
    final isEssentiel = section.kind == SectionKind.essentiel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionBanner(
          title: section.label,
          accent: section.accent,
          blurb: bannerBlurb,
          icon: bannerIcon ?? Icons.article_outlined,
        ),
        ...visible.map(
          (article) => FluxContinuArticleCard(
            article: article,
            isEssentiel: isEssentiel,
            onTap: () => onTapArticle(article),
          ),
        ),
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
}
