import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../soutien_copy.dart';

/// Fil vers la mission depuis les murs de feature : une ligne « financer une
/// info indépendante » + lien « Notre histoire → » vers l'écran Soutien.
class MissionCard extends StatelessWidget {
  const MissionCard({super.key, required this.text, required this.onOurStory});

  final String text;
  final VoidCallback onOurStory;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.primary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.primary.withValues(alpha: 0.15)),
      ),
      child: Text.rich(
        TextSpan(
          text: '$text ',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colors.textSecondary,
                height: 1.5,
              ),
          children: [
            WidgetSpan(
              alignment: PlaceholderAlignment.baseline,
              baseline: TextBaseline.alphabetic,
              child: GestureDetector(
                onTap: onOurStory,
                child: Text(
                  SoutienCopy.missionLinkLabel,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.primary,
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
