import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import 'essentiel_pill.dart';

/// Hero plein-page de la page Digest. Reprend la mise en page de la preview
/// card du feed (pill "L'ESSENTIEL" + grand titre serif + meta + illustration
/// facteur ancrée bottom-right) sans wrapper carte ni perforation, posé
/// directement sur le fond de la page.
class DigestHero extends StatelessWidget {
  final int articleCount;
  final DateTime targetDate;

  const DigestHero({
    super.key,
    required this.articleCount,
    required this.targetDate,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 200,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          // Illustration facteur, ancrée bottom-right (flush coin).
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Image.asset(
                'assets/notifications/facteur_avatar.png',
                height: 150,
                fit: BoxFit.contain,
              ),
            ),
          ),
          // Pill "L'ESSENTIEL" en haut à gauche.
          Positioned(
            top: 16,
            left: 16,
            child: EssentielPill(colors: colors, isDark: isDark),
          ),
          // Titre + caption en bas à gauche.
          Positioned(
            left: 16,
            right: 140,
            bottom: 18,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  "L'essentiel du jour",
                  style: FacteurTypography.serifTitle(colors.textPrimary)
                      .copyWith(fontSize: 32, height: 1.1),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Text(
                  '$articleCount articles · ${formatDigestDate(targetDate)}',
                  style:
                      FacteurTypography.stamp(colors.textTertiary).copyWith(
                    fontSize: 11,
                    letterSpacing: 1.2,
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
