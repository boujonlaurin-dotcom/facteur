import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Closing card displayed after the four Flux Continu sections.
///
/// Visual: "FIN DE TOURNÉE" stamp tilted -2°, then a Fraunces heading and
/// a quiet stat about the tournée length. The CTA scrolls the user into
/// the feed continuation rendered just below.
class ClosingCardV18 extends StatelessWidget {
  final int articleCount;
  final VoidCallback? onContinue;

  const ClosingCardV18({
    super.key,
    required this.articleCount,
    this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 30, 18, 24),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Transform.rotate(
            angle: -2 * math.pi / 180,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border:
                    Border.all(color: const Color(0xFF2E7D32), width: 1.5),
              ),
              child: Text(
                'FIN DE TOURNÉE',
                style: GoogleFonts.courierPrime(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2E7D32),
                  letterSpacing: 1.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Vous êtes à jour',
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _stepLabel(articleCount),
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onContinue,
              child: const Text('Continuer le feed'),
            ),
          ),
        ],
      ),
    );
  }

  String _stepLabel(int count) {
    if (count <= 0) return 'Tournée terminée';
    final plural = count > 1 ? 's' : '';
    return '$count étape$plural parcourue$plural';
  }
}
