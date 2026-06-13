import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/grille_models.dart';

/// Distribution des essais du quartier (`.gl-dist`) — une barre par nombre
/// d'essais, la ligne du joueur (`score == monScore`) surlignée en ocre avec
/// le suffixe « · toi ».
///
/// Les barres sont **normalisées sur le score le plus fréquent** (la barre la
/// plus haute remplit toute la largeur, les autres sont proportionnelles) pour
/// que les ordres de grandeur soient lisibles d'un coup d'œil. Une barre non
/// nulle garde une largeur minimale pour rester visible.
class LeaderboardDistribution extends StatelessWidget {
  const LeaderboardDistribution({
    super.key,
    required this.distribution,
    required this.monScore,
  });

  final List<GrilleDistributionItem> distribution;
  final String monScore;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final maxPct = distribution.fold<int>(0, (m, d) => math.max(m, d.pct));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '— EN COMBIEN D’ESSAIS LE QUARTIER A TROUVÉ —',
          style: GoogleFonts.courierPrime(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1,
            color: c.textTertiary,
          ),
        ),
        const SizedBox(height: 10),
        for (final d in distribution) _row(context, d, maxPct),
      ],
    );
  }

  Widget _row(BuildContext context, GrilleDistributionItem d, int maxPct) {
    final c = context.facteurColors;
    final moi = d.score == monScore;
    // Proportionnel au plus fréquent ; min 8 % de largeur pour qu'une barre
    // non nulle reste visible, 0 % → barre vide.
    final factor = (maxPct == 0 || d.pct == 0)
        ? 0.0
        : (d.pct / maxPct).clamp(0.08, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          SizedBox(
            width: 30,
            child: Text(
              d.score == 'X' ? 'Raté' : '${d.score} ess.',
              style: GoogleFonts.courierPrime(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: c.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FacteurRadius.small),
              child: Container(
                height: 15,
                color: c.backgroundSecondary,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: factor,
                  child: Container(
                    decoration: BoxDecoration(
                      color: moi ? c.primary : GrilleConstants.gauge,
                      borderRadius: BorderRadius.circular(FacteurRadius.small),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 44,
            child: Text(
              moi ? '${d.pct}% · toi' : '${d.pct}%',
              textAlign: TextAlign.right,
              style: GoogleFonts.courierPrime(
                fontSize: 10,
                color: c.textTertiary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
