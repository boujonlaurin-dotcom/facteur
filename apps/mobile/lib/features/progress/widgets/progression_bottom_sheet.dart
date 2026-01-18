import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_button.dart';

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
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.all(24),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colors.textSecondary.withOpacity(0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 24),

            // Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIcons.student(PhosphorIconsStyle.duotone),
                size: 32,
                color: colors.primary,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Transformez votre lecture en compétence',
              style: textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Subtitle
            RichText(
              textAlign: TextAlign.center,
              text: TextSpan(
                style: textTheme.bodyLarge?.copyWith(
                  color: colors.textSecondary,
                ),
                children: [
                  const TextSpan(text: 'Vous venez de lire sur '),
                  TextSpan(
                    text: topicName,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  const TextSpan(
                      text:
                          '. Souhaitez-vous suivre ce thème et tester vos connaissances ?'),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Actions
            FacteurButton(
              label: 'Suivre & Lancer Quiz',
              icon: PhosphorIcons.lightning(PhosphorIconsStyle.bold),
              onPressed: onFollow,
            ),
            const SizedBox(height: 12),
            TextButton(
              onPressed: onDismiss,
              style: TextButton.styleFrom(
                foregroundColor: colors.textSecondary,
              ),
              child: Text(
                'Non, merci',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
