import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../../widgets/design/facteur_button.dart';

class ProgressionBottomSheet extends StatelessWidget {
  final String topicName;
  final VoidCallback onFollow;
  final VoidCallback onExplore;
  final VoidCallback onDismiss;

  const ProgressionBottomSheet({
    super.key,
    required this.topicName,
    required this.onFollow,
    required this.onExplore,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Handle bar
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Icon + Title
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.primary.withOpacity(0.1),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    PhosphorIcons.chartLineUp(PhosphorIconsStyle.fill),
                    color: colors.primary,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Tu veux progresser ?',
                        style: textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Approfondis le sujet "$topicName"',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),

            // Main Action: Follow
            FacteurButton(
              label: 'Suivre ce thème',
              icon: PhosphorIcons.plus(PhosphorIconsStyle.bold),
              onPressed: onFollow,
              type: FacteurButtonType.primary,
            ),
            const SizedBox(height: 12),

            // Secondary Action: Explore
            FacteurButton(
              label: 'Explorer le thème',
              icon: PhosphorIcons.compass(PhosphorIconsStyle.bold),
              onPressed: onExplore,
              type: FacteurButtonType.secondary,
            ),
            const SizedBox(height: 12),

            // Dismiss
            TextButton(
              onPressed: onDismiss,
              child: Text(
                'Non merci',
                style: textTheme.labelLarge?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
