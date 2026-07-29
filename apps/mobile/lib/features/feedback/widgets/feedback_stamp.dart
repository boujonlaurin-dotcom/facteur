import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Tampon encadré légèrement roté, idiome postal du produit (cf.
/// « FIN DE TOURNÉE » sur `ClosingCardV18`).
///
/// Variante `primary` du feature feedback : contrairement à `CompletionStamp`
/// (vert `kStampGreen`, cachet de lecture aboutie), celui-ci reprend la couleur
/// primaire. Partagé par la carte de fin de tournée et la modale d'invitation.
class FeedbackStamp extends StatelessWidget {
  final String label;

  const FeedbackStamp({super.key, required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Transform.rotate(
      angle: -2 * math.pi / 180,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          border: Border.all(color: colors.primary, width: 1.5),
        ),
        child: Text(
          label,
          style: GoogleFonts.courierPrime(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            color: colors.primary,
            letterSpacing: 2.0,
          ),
        ),
      ),
    );
  }
}
