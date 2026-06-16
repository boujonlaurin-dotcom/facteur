import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

/// Teaser statique du futur classement des facteurs (PR2). Non tappable,
/// design aligné sur grille/widgets/leaderboard_hero.dart pour la cohérence
/// future, en version désaturée.
class LeaderboardTeaserCard extends StatelessWidget {
  const LeaderboardTeaserCard({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      margin: const EdgeInsets.only(top: 6, bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.border.withOpacity(0.6)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Column(
        children: [
          Container(
            decoration: BoxDecoration(
              color: colors.textTertiary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.pill),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  PhosphorIcons.medal(PhosphorIconsStyle.fill),
                  size: 14,
                  color: colors.textTertiary,
                ),
                const SizedBox(width: 6),
                Text(
                  'CLASSEMENT DES FACTEURS',
                  style: GoogleFonts.courierPrime(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: colors.textTertiary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Le classement des meilleurs facteurs de la commu arrive bientôt !',
            textAlign: TextAlign.center,
            style: GoogleFonts.dmSans(
              fontSize: 13,
              height: 1.4,
              color: colors.textSecondary,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.pill),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            child: Text(
              'BIENTÔT',
              style: GoogleFonts.courierPrime(
                fontSize: 9.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: colors.primary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
