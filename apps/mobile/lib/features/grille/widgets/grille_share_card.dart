import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/grille_models.dart';
import 'dashed_border.dart';
import 'mot_share_grid.dart';

/// La feuille de partage capturable (`.gp-sheet.mot-share-sheet`).
///
/// Enveloppée dans un [RepaintBoundary] (clé [boundaryKey]) pour préparer
/// l'export image en follow-up (`toImage`). En MVP on partage le **texte**.
class GrilleShareCard extends StatelessWidget {
  const GrilleShareCard({
    super.key,
    required this.numero,
    required this.dateCourt,
    required this.score,
    required this.essais,
    this.boundaryKey,
  });

  final String numero;
  final String dateCourt;

  /// Score affiché (`3/6` ou `X/6`).
  final String score;
  final List<GrilleEssai> essais;
  final GlobalKey? boundaryKey;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;

    final sheet = Container(
      decoration: BoxDecoration(
        color: c.backgroundPrimary,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: CustomPaint(
        painter: DashedRRectPainter(
          color: c.border,
          strokeWidth: 1,
          radius: FacteurRadius.large,
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 26, 24, 26),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'La Grille du jour',
                style: GoogleFonts.fraunces(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.4,
                  color: c.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                '$numero · $dateCourt · $score'.toUpperCase(),
                style: GoogleFonts.courierPrime(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: c.textTertiary,
                ),
              ),
              const SizedBox(height: 16),
              MotShareGrid(essais: essais),
              const SizedBox(height: 16),
              _wordmark(context),
              const SizedBox(height: 2),
              Text(
                '— ta grille du jour, sans spoiler le mot',
                textAlign: TextAlign.center,
                style: GoogleFonts.courierPrime(
                  fontSize: 9,
                  letterSpacing: 0.8,
                  color: c.textTertiary,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return RepaintBoundary(key: boundaryKey, child: sheet);
  }

  Widget _wordmark(BuildContext context) {
    final c = context.facteurColors;
    return Text.rich(
      TextSpan(
        style: GoogleFonts.fraunces(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.5,
          color: c.textPrimary,
        ),
        children: [
          TextSpan(text: 'F', style: TextStyle(color: c.primary)),
          const TextSpan(text: 'acteur'),
        ],
      ),
    );
  }
}
