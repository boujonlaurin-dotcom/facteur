import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../../digest/models/digest_models.dart';

/// Citation du jour — clôture éditoriale de la Tournée du jour, rendue juste
/// avant `ClosingCardV18`. Pool YAML curé côté backend, sélection
/// déterministe seed = user_id + date (même citation toute la journée).
///
/// Style aligné sur `ClosingCardV18` (surface, radius 16, shadow alpha 0.06)
/// mais nettement plus sobre : tampon brun chaud distinct du vert "fin de
/// tournée", pas de CTA, pas d'illustration.
class CitationDuJourCard extends StatelessWidget {
  /// Brun chaud du tampon « CITATION DU JOUR ». Exposé pour que l'onglet sticky
  /// « Citation du jour » réutilise exactement l'accent de la carte.
  static const Color stampColor = Color(0xFF8D6E63);

  final QuoteResponse quote;

  const CitationDuJourCard({super.key, required this.quote});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 24, 18, 8),
      clipBehavior: Clip.antiAlias,
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
      child: Padding(
        padding: const EdgeInsets.fromLTRB(22, 22, 22, 22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.rotate(
              angle: -2 * math.pi / 180,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  border: Border.all(color: stampColor, width: 1.5),
                ),
                child: Text(
                  'CITATION DU JOUR',
                  style: GoogleFonts.courierPrime(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: stampColor,
                    letterSpacing: 2.0,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                '« ${quote.text} »',
                textAlign: TextAlign.center,
                style: GoogleFonts.fraunces(
                  fontSize: 18,
                  fontStyle: FontStyle.italic,
                  height: 1.45,
                  color: colors.textPrimary,
                ),
              ),
            ),
            const SizedBox(height: 14),
            Container(
              height: 1,
              width: 24,
              color: colors.textPrimary.withValues(alpha: 0.08),
            ),
            const SizedBox(height: 10),
            Text(
              _attribution(quote),
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                height: 1.4,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _attribution(QuoteResponse q) {
    final source = q.source;
    if (source == null || source.isEmpty) return '— ${q.author}';
    return '— ${q.author}, $source';
  }
}
