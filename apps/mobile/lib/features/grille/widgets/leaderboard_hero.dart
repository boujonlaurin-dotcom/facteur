import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/grille_models.dart';

/// En-tête du classement (`.gl-hero`) : badge percentile, grand chiffre, ligne
/// « devant N% des Fact·eur·isses ».
class LeaderboardHero extends StatelessWidget {
  const LeaderboardHero({super.key, required this.leaderboard});

  final GrilleLeaderboardResponse leaderboard;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final l = leaderboard;
    final solved = l.monScoreInt != null;

    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: const [
          BoxShadow(color: Color(0x1A000000), blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: c.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.pill),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIcons.medal(PhosphorIconsStyle.fill),
                  size: 14,
                  color: c.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  'TOP ${l.percentile}% AUJOURD’HUI',
                  style: GoogleFonts.courierPrime(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: c.primary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '${l.percentile}',
                  style: GoogleFonts.fraunces(
                    fontSize: 40,
                    fontWeight: FontWeight.w700,
                    height: 1,
                    letterSpacing: -1,
                    color: c.textPrimary,
                  ),
                ),
                TextSpan(
                  text: '%',
                  style: GoogleFonts.fraunces(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: c.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          _who(context, solved),
        ],
      ),
    );
  }

  Widget _who(BuildContext context, bool solved) {
    final c = context.facteurColors;
    final base = FacteurTypography.bodyMedium(c.textSecondary)
        .copyWith(fontSize: 14);
    final bold =
        base.copyWith(color: c.textPrimary, fontWeight: FontWeight.w700);
    if (solved) {
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'Trouvé en '),
            TextSpan(text: '${leaderboard.monScore} essais', style: bold),
            const TextSpan(text: ' — devant '),
            TextSpan(text: '${100 - leaderboard.percentile}%', style: bold),
            const TextSpan(text: ' des Fact·eur·isses'),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
    return Text(
      'Pas trouvé aujourd’hui — mais tu étais dans la tournée. On remet ça demain.',
      style: base,
      textAlign: TextAlign.center,
    );
  }
}
