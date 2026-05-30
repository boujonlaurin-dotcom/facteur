import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';
import '../models/grille_models.dart';
import 'dashed_border.dart';
import 'mot_grid.dart';

/// Vue de résultat (`GMotResultat`, sans `CartePlusLoin`) : cachet de verdict,
/// titre, sous-titre, grille révélée et carte « pourquoi » (voix Facteur).
class GrilleResultView extends StatelessWidget {
  const GrilleResultView({
    super.key,
    required this.today,
    this.animateReveal = false,
  });

  final GrilleTodayResponse today;

  /// Joue le flip de la dernière ligne (arrivée fraîche depuis le jeu).
  final bool animateReveal;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final solved = today.isSolved;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _Cachet(solved: solved),
        const SizedBox(height: 16),
        Text(
          solved ? 'Mot livré.' : 'Mot non distribué.',
          style: GoogleFonts.fraunces(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.4,
            color: c.textPrimary,
          ),
        ),
        const SizedBox(height: 5),
        _subtitle(context, solved),
        const SizedBox(height: 20),
        MotGrid(
          longueur: today.longueur,
          essaisMax: today.essaisMax,
          premiereLettre: today.premiereLettre,
          essais: today.essais,
          variant: MotGridVariant.resultat,
          revealRow:
              animateReveal && solved ? today.essais.length - 1 : -1,
        ),
        const SizedBox(height: 18),
        if (today.pourquoi != null) _pourquoi(context),
      ],
    );
  }

  Widget _subtitle(BuildContext context, bool solved) {
    final c = context.facteurColors;
    final base = FacteurTypography.bodyMedium(c.textSecondary)
        .copyWith(fontSize: 14);
    final bold = base.copyWith(
      color: c.textPrimary,
      fontWeight: FontWeight.w700,
    );
    if (solved) {
      final n = today.nbEssais;
      return Text.rich(
        TextSpan(
          style: base,
          children: [
            const TextSpan(text: 'Trouvé en '),
            TextSpan(text: '$n', style: bold),
            TextSpan(text: ' essai${n > 1 ? 's' : ''} sur ${today.essaisMax}.'),
          ],
        ),
        textAlign: TextAlign.center,
      );
    }
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          const TextSpan(text: 'Le mot du jour était '),
          TextSpan(text: today.mot ?? '', style: bold),
          const TextSpan(text: '.'),
        ],
      ),
      textAlign: TextAlign.center,
    );
  }

  Widget _pourquoi(BuildContext context) {
    final c = context.facteurColors;
    return Container(
      decoration: BoxDecoration(
        color: c.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: const [
          BoxShadow(
            color: Color(0x1A000000),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: const BoxDecoration(
              color: GrilleConstants.avatarFallback,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  today.mot ?? '',
                  style: GoogleFonts.fraunces(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                    color: c.primary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '« ${today.pourquoi} »',
                  style: GoogleFonts.fraunces(
                    fontSize: 14,
                    fontStyle: FontStyle.italic,
                    height: 1.5,
                    color: c.textSecondary,
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

/// Cachet circulaire de verdict (`.mv-cachet`) — ✓ Livré / ✕ Manqué.
class _Cachet extends StatelessWidget {
  const _Cachet({required this.solved});
  final bool solved;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final color = solved ? c.success : c.error;
    return Transform.rotate(
      angle: -9 * math.pi / 180,
      child: Container(
        width: 84,
        height: 84,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: color, width: 2.5),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned.fill(
              child: Padding(
                padding: const EdgeInsets.all(5),
                child: CustomPaint(
                  painter: DashedRRectPainter(
                    color: color.withValues(alpha: 0.45),
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
                  style: TextStyle(
                    fontSize: 26,
                    height: 1,
                    color: color,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  solved ? 'LIVRÉ' : 'MANQUÉ',
                  style: GoogleFonts.courierPrime(
                    fontSize: 9,
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
