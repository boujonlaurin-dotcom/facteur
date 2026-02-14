import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../core/ui/notification_service.dart';
import '../../feed/providers/feed_provider.dart';
import '../models/digest_models.dart';

/// Bottom sheet widget showing "Pourquoi cet article?" with scoring breakdown
/// Adapted from feed's PersonalizationSheet but for DigestItem
class DigestPersonalizationSheet extends ConsumerWidget {
  final DigestItem item;

  const DigestPersonalizationSheet({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final reason = item.recommendationReason;

    if (reason == null) {
      return _buildNoReasonView(context, ref, colors);
    }

    return Container(
      padding: const EdgeInsets.only(top: 24, bottom: 40, left: 20, right: 20),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          _buildDragHandle(colors),
          const SizedBox(height: 20),

          // Header with icon, title and total score
          _buildHeader(context, colors, reason),
          const SizedBox(height: 24),

          // Breakdown list
          ...reason.breakdown.map((contribution) =>
              _buildContributionRow(context, colors, contribution)),

          // Divider and actions
          if (item.source != null) ...[
            const SizedBox(height: 16),
            Divider(color: colors.border),
            const SizedBox(height: 16),
            _buildActions(context, ref, colors, item),
          ],
        ],
      ),
    );
  }

  Widget _buildDragHandle(FacteurColors colors) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: colors.textTertiary.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(
    BuildContext context,
    FacteurColors colors,
    DigestRecommendationReason reason,
  ) {
    return Row(
      children: [
        Icon(
          PhosphorIcons.question(PhosphorIconsStyle.bold),
          color: colors.primary,
          size: 24,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            'Pourquoi cet article ?',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        if (reason.scoreTotal > 0)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: colors.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              '${reason.scoreTotal.toInt()} pts',
              style: TextStyle(
                color: colors.primary,
                fontSize: 14,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildContributionRow(
    BuildContext context,
    FacteurColors colors,
    DigestScoreBreakdown contribution,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            contribution.isPositive
                ? PhosphorIcons.trendUp(PhosphorIconsStyle.bold)
                : PhosphorIcons.trendDown(PhosphorIconsStyle.bold),
            color: contribution.isPositive ? colors.success : colors.error,
            size: 16,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              contribution.label,
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 15,
              ),
            ),
          ),
          Text(
            '${contribution.points > 0 ? '+' : ''}${contribution.points.toInt()}',
            style: TextStyle(
              color: colors.textPrimary,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActions(
    BuildContext context,
    WidgetRef ref,
    FacteurColors colors,
    DigestItem item,
  ) {
    final source = item.source;
    final theme = source?.theme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Personnaliser mon flux'.toUpperCase(),
          style: TextStyle(
            color: colors.textSecondary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 12),

        // Mute source action
        if (source != null && source.id != null && source.id!.isNotEmpty)
          _buildActionOption(
            context,
            icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
            label: 'Moins de ${source.name}',
            onTap: () async {
              Navigator.pop(context);
              try {
                await ref
                    .read(feedProvider.notifier)
                    .muteSourceById(source.id!);
                NotificationService.showInfo('Source ${source.name} masquée');
              } catch (e) {
                NotificationService.showError(
                    'Impossible de masquer la source');
              }
            },
            colors: colors,
          ),

        // Mute theme action
        if (theme != null && theme.isNotEmpty)
          _buildActionOption(
            context,
            icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
            label: 'Moins sur le thème "${_getThemeLabel(theme)}"',
            onTap: () async {
              Navigator.pop(context);
              try {
                await ref.read(feedProvider.notifier).muteTheme(theme);
                NotificationService.showInfo('Thème masqué');
              } catch (e) {
                NotificationService.showError('Impossible de masquer le thème');
              }
            },
            colors: colors,
          ),

        // Mute topic actions (topics ML granulaires, max 2)
        for (final topicSlug in item.topics.take(2))
          if (_getThemeLabel(theme ?? '').toLowerCase() !=
              getTopicLabel(topicSlug).toLowerCase())
            _buildActionOption(
              context,
              icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
              label: 'Moins sur "${getTopicLabel(topicSlug)}"',
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(feedProvider.notifier).muteTopic(topicSlug);
                  NotificationService.showInfo('Sujet masqué');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer le sujet');
                }
              },
              colors: colors,
            ),
      ],
    );
  }

  Widget _buildActionOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required FacteurColors colors,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: colors.textPrimary, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoReasonView(
      BuildContext context, WidgetRef ref, FacteurColors colors) {
    return Container(
      padding: const EdgeInsets.only(top: 24, bottom: 40, left: 20, right: 20),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildDragHandle(colors),
          const SizedBox(height: 20),

          // Header — still show a useful title
          Row(
            children: [
              Icon(
                PhosphorIcons.sliders(PhosphorIconsStyle.bold),
                color: colors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Personnaliser',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            'Ajustez vos préférences pour cet article.',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 14,
            ),
          ),

          // Always show personalization actions if source is available
          if (item.source != null) ...[
            const SizedBox(height: 16),
            Divider(color: colors.border),
            const SizedBox(height: 16),
            _buildActions(context, ref, colors, item),
          ],
        ],
      ),
    );
  }

  String _getThemeLabel(String slug) {
    const translations = {
      'tech': 'Tech',
      'international': 'International',
      'science': 'Science',
      'culture': 'Culture',
      'politics': 'Politique',
      'society': 'Société',
      'environment': 'Environnement',
      'economy': 'Économie',
    };
    return translations[slug.toLowerCase()] ?? slug;
  }
}
