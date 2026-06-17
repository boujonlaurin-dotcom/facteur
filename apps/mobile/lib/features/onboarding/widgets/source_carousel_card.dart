import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../config/theme.dart';
import '../../sources/widgets/source_logo_avatar.dart';
import '../data/source_recommender.dart';
import 'source_reco_tag.dart';

/// Carte portrait d'une source recommandée, pensée pour le carrousel horizontal
/// de l'onboarding (`SourceCarousel`). Plus aérée que la `Row` dense de
/// [SourceRecommendationCard] : logo + nom + pastille de biais en tête, les
/// **aspects matchés** (tags du recommender) mis en valeur au cœur, et une zone
/// de sélection claire (≥44px).
///
/// Tap sur la carte → [onInfoTap] (modale détail). Tap sur le cercle → [onToggle].
class SourceCarouselCard extends StatelessWidget {
  final RecommendedSource recommendation;
  final bool isSelected;
  final VoidCallback onToggle;
  final VoidCallback onInfoTap;

  /// Affiche les tags/raison de match. Faux pour le catalogue brut (section 3),
  /// dont les sources n'ont pas de raison de reco spécifique.
  final bool showReason;

  const SourceCarouselCard({
    super.key,
    required this.recommendation,
    required this.isSelected,
    required this.onToggle,
    required this.onInfoTap,
    this.showReason = true,
  });

  /// Nombre max de tags affichés (garde une hauteur lisible et bornée).
  static const int _maxTags = 3;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final source = recommendation.source;
    final tags = showReason
        ? recommendation.tags.take(_maxTags).toList()
        : const <RecommendationTag>[];

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onInfoTap();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        curve: Curves.easeOut,
        padding: const EdgeInsets.all(FacteurSpacing.space4),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(
            color: isSelected
                ? colors.primary.withOpacity(0.4)
                : colors.border.withOpacity(0.3),
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── En-tête : logo + nom + sélection ──────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SourceLogoAvatar(source: source, size: 40, radius: 10),
                const SizedBox(width: FacteurSpacing.space3),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      source.name,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                            color: colors.textPrimary,
                            fontWeight: FontWeight.w700,
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                _selectionCircle(context),
              ],
            ),

            // ── Pastille de biais (display-only) ──────────────────────────
            if (source.biasStance != 'unknown') ...[
              const SizedBox(height: FacteurSpacing.space2),
              Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: source.getBiasColor(),
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    source.getBiasLabel(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                  ),
                ],
              ),
            ],

            const SizedBox(height: FacteurSpacing.space3),

            // ── Cœur : aspects matchés (tags) ou raison ───────────────────
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: SingleChildScrollView(
                  physics: const NeverScrollableScrollPhysics(),
                  child: _matchBody(context, tags),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _matchBody(BuildContext context, List<RecommendationTag> tags) {
    final colors = context.facteurColors;
    if (tags.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [for (final tag in tags) SourceRecoTag(tag: tag)],
      );
    }
    if (showReason && recommendation.reason.isNotEmpty) {
      return Text(
        recommendation.reason,
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: colors.textSecondary,
              fontStyle: recommendation.category == SourceCategory.gem
                  ? FontStyle.italic
                  : FontStyle.normal,
            ),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
      );
    }
    return const SizedBox.shrink();
  }

  Widget _selectionCircle(BuildContext context) {
    final colors = context.facteurColors;
    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        onToggle();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: AnimatedContainer(
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
      ),
    );
  }
}
