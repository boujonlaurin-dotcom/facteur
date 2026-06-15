import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/grille_models.dart';
import 'dashed_border.dart';
import 'grille_countdown.dart';

/// Écran « Déjà joué aujourd'hui » (`GDejaJoue`) : sceau, message et compte à
/// rebours live jusqu'au prochain mot. Affiché au cold-load d'une partie déjà
/// terminée (vs Résultat juste après la fin).
class GrilleDejaJoueView extends StatelessWidget {
  const GrilleDejaJoueView({super.key, required this.today});

  final GrilleTodayResponse today;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final solved = today.isSolved;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          _Seal(solved: solved),
          const SizedBox(height: 22),
          Text(
            solved ? 'Mot du jour trouvé.' : 'Mot du jour manqué.',
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 26,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.5,
              color: c.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            _subtitle(solved),
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 15,
              fontStyle: FontStyle.italic,
              height: 1.55,
              color: c.textSecondary,
            ),
          ),
          const SizedBox(height: 22),
          GrilleCountdown(initialSeconds: today.prochainMotDansSec),
        ],
      ),
    );
  }

  String _subtitle(bool solved) {
    if (solved) {
      final n = today.nbEssais;
      return '« Tu as bouclé la grille d’aujourd’hui — $n essai${n > 1 ? 's' : ''}, '
          'bien joué. Je te poste un mot tout neuf demain matin. »';
    }
    final mot = today.mot ?? '';
    return '« Le mot du jour était « $mot ». Pas grave — il était sous tes yeux '
        'toute la tournée. Je te poste un mot tout neuf demain matin. »';
  }
}

/// Sceau circulaire « Trouvé / Raté » (`.gd-seal`).
class _Seal extends StatelessWidget {
  const _Seal({required this.solved});
  final bool solved;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final color = c.textStamp;
    return Transform.rotate(
      angle: -7 * math.pi / 180,
      child: Container(
        width: 116,
        height: 116,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: CustomPaint(
                  painter: DashedRRectPainter(
                    color: color.withValues(alpha: 0.4),
                    strokeWidth: 1.5,
                    radius: 999,
                  ),
                ),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  solved ? '✓' : '✕',
                  style: TextStyle(fontSize: 30, color: color, height: 1),
                ),
                const SizedBox(height: 3),
                Text(
                  solved ? 'TROUVÉ' : 'RATÉ',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.5,
                    color: color,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
