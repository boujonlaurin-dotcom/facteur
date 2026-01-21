import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../models/content_model.dart';
import 'feed_card.dart';

/// Section Briefing Quotidien avec design premium.
///
/// Affiche les 3 articles les plus importants du jour dans un container
/// visuellement distinct avec gradient et cartes full-size.
class BriefingSection extends StatelessWidget {
  final List<DailyTop3Item> briefing;
  final void Function(DailyTop3Item) onItemTap;

  const BriefingSection({
    super.key,
    required this.briefing,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    if (briefing.isEmpty) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final allConsumed = briefing.every((item) => item.isConsumed);

    // Si tout est lu, afficher une version réduite
    if (allConsumed) {
      return _buildCollapsedSection(context, colors);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header premium
          _buildHeader(context, colors),
          const SizedBox(height: 16),

          // Container premium avec gradient border
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  colors.primary.withOpacity(0.08),
                  colors.primary.withOpacity(0.02),
                ],
              ),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: colors.primary.withOpacity(0.15),
                width: 1.5,
              ),
            ),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                for (int i = 0; i < briefing.length; i++) ...[
                  _buildBriefingItem(context, briefing[i], i),
                  if (i < briefing.length - 1) const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, FacteurColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.primary,
                  colors.primary.withOpacity(0.8),
                ],
              ),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              PhosphorIcons.target(PhosphorIconsStyle.fill),
              size: 18,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "L'Essentiel du Jour",
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
                Text(
                  "Sélectionné pour vous",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
          // Progress indicator
          _buildProgressIndicator(colors),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(FacteurColors colors) {
    final readCount = briefing.where((item) => item.isConsumed).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$readCount/${briefing.length}',
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 13,
            ),
          ),
          const SizedBox(width: 6),
          Icon(
            PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
            size: 14,
            color: colors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildBriefingItem(
      BuildContext context, DailyTop3Item item, int index) {
    final colors = context.facteurColors;

    return Stack(
      children: [
        // FeedCard standard (full-size)
        Opacity(
          opacity: item.isConsumed ? 0.6 : 1.0,
          child: FeedCard(
            content: item.content,
            onTap: () => onItemTap(item),
          ),
        ),

        // Badge TOP X en overlay
        Positioned(
          top: 8,
          left: 8,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colors.primary,
                  colors.primary.withOpacity(0.85),
                ],
              ),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(
                  color: colors.primary.withOpacity(0.3),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '#${index + 1}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w700,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  _getReasonEmoji(item.reason),
                  style: const TextStyle(fontSize: 11),
                ),
              ],
            ),
          ),
        ),

        // Check mark if consumed
        if (item.isConsumed)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: colors.success,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: colors.success.withOpacity(0.3),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check,
                size: 14,
                color: Colors.white,
              ),
            ),
          ),
      ],
    );
  }

  String _getReasonEmoji(String reason) {
    switch (reason.toLowerCase()) {
      case 'à la une':
        return '📰';
      case 'sujet tendance':
        return '🔥';
      case 'source suivie':
        return '⭐';
      default:
        return '✨';
    }
  }

  Widget _buildCollapsedSection(BuildContext context, FacteurColors colors) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.success.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: colors.success.withOpacity(0.2),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: colors.success,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.check,
              size: 16,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Briefing terminé ! ✅",
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.success,
                      ),
                ),
                Text(
                  "Rendez-vous demain à 8h pour votre prochain briefing",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
