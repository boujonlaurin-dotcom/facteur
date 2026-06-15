import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';
import 'tournee_cta_buttons.dart';

/// Closing block displayed at the very bottom of a Tournée detail screen
/// (theme or digest "Voir + de…" page) once the scroll is fully exhausted.
///
/// Reuses the visual shell of [ClosingCardV18] — light surface card, 16px
/// radius, subtle drop shadow, Fraunces 22 heading + DM Sans 13 sub — so the
/// dedicated-page footers feel like a satellite of the main closing card
/// instead of a foreign element.
class ThemeDetailFooter extends StatelessWidget {
  final String sectionLabel;
  final FluxSection? nextSection;
  final VoidCallback onTapBackToTournee;
  final VoidCallback? onTapNextSection;

  const ThemeDetailFooter({
    super.key,
    required this.sectionLabel,
    required this.nextSection,
    required this.onTapBackToTournee,
    this.onTapNextSection,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final hasNext = nextSection != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(18, 24, 18, 24),
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
        padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Vous avez fait le tour de $sectionLabel',
              textAlign: TextAlign.center,
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                height: 1.15,
                letterSpacing: -0.4,
                color: colors.textPrimary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Rien de nouveau dans vos sources aujourd’hui',
              textAlign: TextAlign.center,
              style: GoogleFonts.dmSans(
                fontSize: 13,
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 20),
            TourneePrimaryButton(
              label: hasNext
                  ? 'Sujet suivant : ${nextSection!.label} →'
                  : 'Retour à la Tournée',
              onTap: hasNext ? onTapNextSection : onTapBackToTournee,
            ),
            if (hasNext) ...[
              const SizedBox(height: 8),
              TourneeGhostButton(
                label: 'Retour à la Tournée',
                onTap: onTapBackToTournee,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
