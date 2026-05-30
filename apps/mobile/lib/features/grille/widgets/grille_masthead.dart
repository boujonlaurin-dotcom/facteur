import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import 'dashed_border.dart';

/// Masthead de l'écran de jeu (`.mot-mast`) : kicker daté, titre serif, filet
/// pointillé, puce d'indice et compteur d'essai.
class GrilleMasthead extends StatelessWidget {
  const GrilleMasthead({
    super.key,
    required this.numero,
    required this.date,
    required this.longueur,
    required this.premiereLettre,
    required this.essaisMax,
    this.essai,
  });

  final String numero;
  final String date;
  final int longueur;
  final String premiereLettre;
  final int essaisMax;

  /// Numéro de l'essai courant (`n / essaisMax`). `null` → compteur masqué.
  final int? essai;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final mono = GoogleFonts.courierPrime(
      fontSize: 10,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.5,
      color: c.textTertiary,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(22, 6, 22, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('$numero · $date'.toUpperCase(), style: mono),
          const SizedBox(height: 6),
          Text(
            'La Grille du jour',
            style: GoogleFonts.fraunces(
              fontSize: 27,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.6,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 9),
          SizedBox(
            height: 2,
            width: double.infinity,
            child: CustomPaint(
              painter: DashedLinePainter(color: c.border, strokeWidth: 2),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(child: _hintChip(context)),
              if (essai != null)
                Text(
                  'Essai $essai / $essaisMax',
                  style: GoogleFonts.courierPrime(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: c.textTertiary,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _hintChip(BuildContext context) {
    final c = context.facteurColors;
    return Container(
      decoration: BoxDecoration(
        color: c.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 5),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.envelopeSimple(),
            size: 13,
            color: c.textStamp,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '$longueur lettres · commence par $premiereLettre'.toUpperCase(),
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.courierPrime(
                fontSize: 10.5,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.6,
                color: c.textStamp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
