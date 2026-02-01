import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';

class PersonalizationSheet extends ConsumerWidget {
  final Content content;

  const PersonalizationSheet({super.key, required this.content});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final reason = content.recommendationReason;
    final theme = content.source.theme;

    // Topic logic: use progressionTopic or derive from Reason if possible.
    final topic = content.progressionTopic;

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
          // Header
          Row(
            children: [
              Icon(PhosphorIcons.question(PhosphorIconsStyle.bold),
                  color: colors.primary, size: 24),
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
              if (reason != null && reason.scoreTotal > 0)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
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
          ),
          const SizedBox(height: 20),

          // Breakdown
          if (reason != null && reason.breakdown.isNotEmpty) ...[
            ...reason.breakdown.map((contribution) => Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Icon(
                        contribution.isPositive
                            ? PhosphorIcons.trendUp(PhosphorIconsStyle.bold)
                            : PhosphorIcons.trendDown(PhosphorIconsStyle.bold),
                        color: contribution.isPositive
                            ? colors.success
                            : colors.error,
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
                )),
            const SizedBox(height: 16),
            Divider(color: colors.border),
            const SizedBox(height: 16),
          ],

          // Actions
          Text(
            'Personnaliser mon flux'.toUpperCase(),
            style: TextStyle(
              color: colors.textSecondary, // Use secondary for section title
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),

          if (content.source.name.isNotEmpty)
            _buildActionOption(
              context,
              icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
              label: 'Moins de ${content.source.name}',
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(feedProvider.notifier).muteSource(content);
                  NotificationService.showInfo(
                      'Source ${content.source.name} masquée');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer la source');
                }
              },
              colors: colors,
            ),

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
                  NotificationService.showError(
                      'Impossible de masquer le thème');
                }
              },
              colors: colors,
            ),

          if (topic != null &&
              topic.isNotEmpty &&
              _normalize(topic) != _normalize(theme ?? ''))
            _buildActionOption(
              context,
              icon: PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
              label: 'Moins sur le sujet "${_getThemeLabel(topic)}"',
              onTap: () async {
                Navigator.pop(context);
                try {
                  await ref.read(feedProvider.notifier).muteTopic(topic);
                  NotificationService.showInfo('Sujet masqué');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer le sujet');
                }
              },
              colors: colors,
            ),

          const SizedBox(height: 8),
        ],
      ),
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

  String _normalize(String input) {
    const withDiacritics =
        'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
    const withoutDiacritics =
        'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';

    var result = input;
    for (int i = 0; i < withDiacritics.length; i++) {
      result = result.replaceAll(withDiacritics[i], withoutDiacritics[i]);
    }
    return result.toLowerCase();
  }
}
