import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import 'essentiel_pill.dart';
import 'lecture_apaisee_pill.dart';

/// Hero plein-page de la page Digest. Pill (Essentiel ou Lecture apaisée) +
/// grand titre serif + meta, avec illustration facteur ancrée bottom-right.
class DigestHero extends StatelessWidget {
  final int articleCount;
  final DateTime targetDate;
  final bool isSerein;

  const DigestHero({
    super.key,
    required this.articleCount,
    required this.targetDate,
    this.isSerein = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final title = isSerein ? 'Une lecture apaisée' : "L'essentiel du jour";

    return SizedBox(
      height: 170,
      child: Stack(
        clipBehavior: Clip.hardEdge,
        children: [
          Positioned(
            right: 0,
            bottom: 0,
            child: IgnorePointer(
              child: Image.asset(
                'assets/notifications/facteur_avatar.png',
                height: 140,
                fit: BoxFit.contain,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 140, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                isSerein
                    ? LectureApaiseePill(isDark: isDark)
                    : EssentielPill(colors: colors, isDark: isDark),
                const SizedBox(height: 6),
                Text(
                  title,
                  style: FacteurTypography.serifTitle(colors.textPrimary)
                      .copyWith(fontSize: 32, height: 1.1),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 14),
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
