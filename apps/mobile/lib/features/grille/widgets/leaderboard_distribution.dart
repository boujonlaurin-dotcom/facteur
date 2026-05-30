import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/grille_models.dart';

/// Distribution des essais du quartier (`.gl-dist`) — une barre par nombre
/// d'essais, la ligne du joueur (`score == monScore`) surlignée en ocre avec
/// le suffixe « · toi ».
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
        const SizedBox(height: 12),
        for (final d in distribution) _row(context, d),
      ],
    );
  }

  Widget _row(BuildContext context, GrilleDistributionItem d) {
    final c = context.facteurColors;
    final moi = d.score == monScore;
    final factor = (d.pct * 2.5 / 100).clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
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
                height: 18,
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
