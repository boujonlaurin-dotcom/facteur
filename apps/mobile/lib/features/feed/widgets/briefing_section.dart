import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../models/content_model.dart';
import 'feed_card.dart';

/// Section Briefing Quotidien avec design premium affiné.
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

    if (allConsumed) {
      return _buildCollapsedSection(context, colors);
    }

    // Calcul du temps de lecture estimé (moyenne 2 min par article si nul)
    final totalSeconds = briefing.fold<int>(0, (sum, item) {
      return sum + (item.content.durationSeconds ?? 120);
    });
    final totalMinutes = (totalSeconds / 60).ceil();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Couleurs adaptatives pour le container
    final containerBgColors = isDark
        ? [const Color(0xFF1A1918), const Color(0xFF2C2A29)] // Obsidian
        : [
            colors.backgroundSecondary,
            colors.backgroundPrimary
          ]; // Papier Premium

    final headerTextColor = isDark ? Colors.white : colors.textPrimary;
    final subheaderTextColor =
        isDark ? Colors.white.withOpacity(0.6) : colors.textSecondary;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: containerBgColors,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? colors.primary.withOpacity(0.3)
              : colors.primary.withOpacity(0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header unifié
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "L'Essentiel du Jour",
                      style: Theme.of(context).textTheme.displaySmall?.copyWith(
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.5,
                            color: headerTextColor,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          PhosphorIcons.clock(PhosphorIconsStyle.regular),
                          size: 14,
                          color: subheaderTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          "$totalMinutes min de lecture",
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: subheaderTextColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              _buildProgressBadge(colors),
            ],
          ),
          const SizedBox(height: 16),

          // Liste des articles
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: briefing.length,
            separatorBuilder: (context, index) => const SizedBox(height: 20),
            itemBuilder: (context, index) {
              final item = briefing[index];
              return _buildRankedCard(context, item, index + 1, isDark);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildProgressBadge(FacteurColors colors) {
    final readCount = briefing.where((item) => item.isConsumed).length;
    final isDone = readCount == briefing.length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isDone ? colors.success : colors.primary,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        "$readCount/${briefing.length}",
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 12,
        ),
      ),
    );
  }

  Widget _buildRankedCard(
      BuildContext context, DailyTop3Item item, int rank, bool isDark) {
    final colors = context.facteurColors;
    final labelColor =
        isDark ? Colors.white.withOpacity(0.5) : colors.textSecondary;
    final dotColor = isDark
        ? Colors.white.withOpacity(0.2)
        : colors.textTertiary.withOpacity(0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Label de rang au-dessus de la carte pour ne pas chevaucher le contenu
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 8),
          child: Row(
            children: [
              Text(
                "N°$rank",
                style: TextStyle(
                  color: colors.primary.withOpacity(isDark ? 0.9 : 1.0),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                item.reason.toUpperCase(),
                style: TextStyle(
                  color: labelColor,
                  fontWeight: FontWeight.w600,
                  fontSize: 11,
                  letterSpacing: 0.5,
                ),
              ),
              const Spacer(),
              if (item.isConsumed)
                Icon(
                  PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.success,
                ),
            ],
          ),
        ),
        // La carte classique
        Opacity(
          opacity: item.isConsumed ? 0.6 : 1.0,
          child: FeedCard(
            content: item.content,
            onTap: () => onItemTap(item),
          ),
        ),
      ],
    );
  }

  Widget _buildCollapsedSection(BuildContext context, FacteurColors colors) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bgColor =
        isDark ? const Color(0xFF1A1918) : colors.backgroundSecondary;

    return Container(
      margin: const EdgeInsets.only(top: 8, bottom: 24),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            bgColor,
            colors.success.withOpacity(isDark ? 0.1 : 0.05),
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: colors.success.withOpacity(0.3),
          width: 1,
        ),
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
            color: colors.success,
            size: 28,
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Briefing terminé !",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : colors.textPrimary,
                      ),
                ),
                Text(
                  "Revenez demain à 8h pour votre prochaine sélection.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: isDark
                            ? Colors.white.withOpacity(0.6)
                            : colors.textSecondary,
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
