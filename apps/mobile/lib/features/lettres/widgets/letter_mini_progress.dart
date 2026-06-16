import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Mini barre de progression des lettres (extraite de letter_row.dart) —
/// partagée entre les rows, le banner feed, le header Progression et la
/// carte profil.
class LetterMiniProgress extends StatelessWidget {
  final double progress;
  final int done;
  final int total;
  final bool dimmed;
  final double height;
  final bool showCount;

  const LetterMiniProgress({
    super.key,
    required this.progress,
    required this.done,
    required this.total,
    this.dimmed = false,
    this.height = 3,
    this.showCount = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final fillColor =
        dimmed ? colors.textTertiary.withOpacity(0.4) : colors.primary;
    return Row(
      children: [
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(
                  height: height,
                  color: Colors.black.withOpacity(0.07),
                ),
                FractionallySizedBox(
                  widthFactor: progress.clamp(0.0, 1.0),
                  child: Container(height: height, color: fillColor),
                ),
              ],
            ),
          ),
        ),
        if (showCount) ...[
          const SizedBox(width: 8),
          Text(
            '$done/$total',
            style: GoogleFonts.courierPrime(
              fontSize: 10,
              fontWeight: FontWeight.w400,
              letterSpacing: 0.5,
              color: colors.textTertiary,
            ),
          ),
        ],
      ],
    );
  }
}
