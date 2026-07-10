import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../data/source_recommender.dart';

/// Petite puce affichant un [RecommendationTag] (thème, « Spécialisé en X »,
/// « Similaire à … », fiable, anti-bruit, serein). Partagée entre la carte
/// liste ([SourceRecommendationCard]) et la carte carrousel
/// ([SourceCarouselCard]) pour éviter toute duplication du style.
///
/// Les puces « pourquoi » (spécialiste / similaire / fiable / anti-bruit)
/// ressortent en teinte primary ; les tags purement thématiques restent
/// neutres.
class SourceRecoTag extends StatelessWidget {
  final RecommendationTag tag;

  const SourceRecoTag({super.key, required this.tag});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    final prefix = switch (tag.type) {
      RecommendationTagType.topic => '',
      RecommendationTagType.specialist => '\u{1F3AF} ',
      RecommendationTagType.antiBruit => '\u{1F507} ',
      RecommendationTagType.fiable => '✓ ',
      RecommendationTagType.serein => '☀ ',
      RecommendationTagType.similar => '≈ ',
    };

    final highlighted = switch (tag.type) {
      RecommendationTagType.specialist ||
      RecommendationTagType.similar ||
      RecommendationTagType.fiable ||
      RecommendationTagType.antiBruit => true,
      _ => false,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: highlighted
            ? colors.primary.withOpacity(0.08)
            : colors.textPrimary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Text(
        '$prefix${tag.label}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: highlighted ? colors.primary : colors.textSecondary,
              fontSize: 11,
              fontWeight: highlighted ? FontWeight.w600 : null,
            ),
      ),
    );
  }
}
