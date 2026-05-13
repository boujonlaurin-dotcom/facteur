import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';

/// Closing card displayed after the four Flux Continu sections.
///
/// Layout per maquette V6 :
/// - "FIN DE TOURNÉE" stamp Courier Prime 10 w700, color/border #2E7D32,
///   rotation -2°.
/// - Heading "Vous êtes à jour" Fraunces 700 24px.
/// - Description (DM Sans 13, line-height 1.5, max-w 280, centered) — "X
///   étape(s) parcourue(s)" or "Tournée terminée" when empty.
/// - Primary CTA "Continuer le feed" (background #D35400) + ghost CTA
///   "Refermer pour aujourd'hui" (border 1.5px rgba(0,0,0,0.1)).
class ClosingCardV18 extends StatelessWidget {
  final int articleCount;
  final VoidCallback? onContinue;
  final VoidCallback? onClose;

  const ClosingCardV18({
    super.key,
    required this.articleCount,
    this.onContinue,
    this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 30, 18, 24),
      padding: const EdgeInsets.fromLTRB(22, 28, 22, 22),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Transform.rotate(
            angle: -2 * math.pi / 180,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                border: Border.all(
                  color: const Color(0xFF2E7D32),
                  width: 1.5,
                ),
              ),
              child: Text(
                'FIN DE TOURNÉE',
                style: GoogleFonts.courierPrime(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: const Color(0xFF2E7D32),
                  letterSpacing: 2.0,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Vous êtes à jour',
            textAlign: TextAlign.center,
            style: GoogleFonts.fraunces(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              height: 1.1,
              letterSpacing: -0.4,
              color: colors.textPrimary,
            ),
          ),
          const SizedBox(height: 8),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 280),
            child: Text(
              _stepLabel(articleCount),
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
          ),
          const SizedBox(height: 20),
          SizedBox(
            width: double.infinity,
            child: _PrimaryButton(
              label: 'Continuer le feed',
              onTap: onContinue,
            ),
          ),
          if (onClose != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: _GhostButton(
                label: "Refermer pour aujourd'hui",
                onTap: onClose,
              ),
            ),
          ],
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

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: const Color(0xFFD35400),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GhostButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;

  const _GhostButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: Colors.black.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          child: Center(
            child: Text(
              label,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
