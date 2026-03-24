import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../widgets/design/facteur_image.dart';
import '../data/source_recommender.dart';

/// Card widget for a recommended source in the onboarding sources screen.
///
/// Tap on the card toggles selection. Tap on the (i) icon opens the detail modal.
/// Shows recommendation tags (topic matches, anti-bruit, fiable, serein) as chips.
class SourceRecommendationCard extends StatelessWidget {
  final RecommendedSource recommendation;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onInfoTap;
  final bool showReason;

  const SourceRecommendationCard({
    super.key,
    required this.recommendation,
    required this.isSelected,
    required this.onToggle,
    required this.onInfoTap,
    this.showReason = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final source = recommendation.source;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onToggle();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          border: Border.all(
            color: isSelected
                ? colors.primary.withValues(alpha: 0.3)
                : colors.border.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            // Logo
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: SizedBox(
                width: 40,
                height: 40,
                child: source.logoUrl != null && source.logoUrl!.isNotEmpty
                    ? FacteurImage(
                        imageUrl: source.logoUrl!,
                        fit: BoxFit.cover,
                        errorWidget: (_) => _buildLogoFallback(colors, source.name),
                      )
                    : _buildLogoFallback(colors, source.name),
              ),
            ),
            const SizedBox(width: FacteurSpacing.space4),

            // Name + bias inline + tags or reason
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + bias inline
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          source.name,
                          style:
                              Theme.of(context).textTheme.labelLarge?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w500,
                                  ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (source.biasStance != 'unknown') ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: source.getBiasColor(),
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 3),
                        Text(
                          source.getBiasLabel(),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.textTertiary,
                                    fontSize: 10,
                                  ),
                        ),
                      ],
                    ],
                  ),

                  // Tags (for matched sources) or reason text (for gems/perspective)
                  if (showReason && recommendation.tags.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: recommendation.tags
                          .map((tag) => _buildTag(context, tag))
                          .toList(),
                    ),
                  ] else if (showReason &&
                      recommendation.reason.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      recommendation.reason,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: colors.textTertiary,
                            fontStyle: recommendation.category ==
                                    SourceCategory.gem
                                ? FontStyle.italic
                                : FontStyle.normal,
                          ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(width: FacteurSpacing.space2),

            // Info button
            GestureDetector(
              onTap: () {
                HapticFeedback.lightImpact();
                onInfoTap();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  PhosphorIcons.info(PhosphorIconsStyle.regular),
                  size: 20,
                  color: colors.textTertiary,
                ),
              ),
            ),

            const SizedBox(width: FacteurSpacing.space2),

            // Selection indicator
            AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: isSelected ? colors.primary : Colors.transparent,
                border: Border.all(
                  color: isSelected ? colors.primary : colors.textTertiary,
                  width: isSelected ? 0 : 1.5,
                ),
                shape: BoxShape.circle,
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 16, color: Colors.white)
                  : null,
            ),
          ],
        ),
      ),
    );
  }

  /// Builds a fallback avatar with the source's initials.
  static Widget _buildLogoFallback(FacteurColors colors, String name) {
    final initials = name
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Container(
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
      ),
      alignment: Alignment.center,
      child: Text(
        initials.isEmpty ? '?' : initials,
        style: TextStyle(
          color: colors.textSecondary,
          fontSize: 14,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  /// Builds a small chip for a recommendation tag.
  Widget _buildTag(BuildContext context, RecommendationTag tag) {
    final colors = context.facteurColors;

    final prefix = switch (tag.type) {
      RecommendationTagType.topic => '',
      RecommendationTagType.antiBruit => '\u{1F507} ',
      RecommendationTagType.fiable => '\u2713 ',
      RecommendationTagType.serein => '\u2600 ',
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Text(
        '$prefix${tag.label}',
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontSize: 11,
            ),
      ),
    );
  }
}
