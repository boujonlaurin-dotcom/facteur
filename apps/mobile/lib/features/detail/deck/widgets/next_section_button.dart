import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';

/// Bouton flottant « on continue » posé sur le **dernier article d'une
/// section** du deck (Story 34.2).
///
/// Reprend la forme du CTA de clôture de la Tournée (`TourneePrimaryButton` :
/// aplat `primary`, DM Sans 13 w600, radius 10) — c'est le même geste éditorial
/// « passer au bloc suivant », il doit se reconnaître. Flottant, il y ajoute
/// seulement l'ombre portée et la largeur intrinsèque : il ne barre pas
/// l'article, il se pose dessus.
class NextSectionButton extends StatelessWidget {
  const NextSectionButton({
    super.key,
    required this.label,
    required this.onTap,
  });

  /// Nom de la section suivante — le bouton dit **où** il mène, jamais
  /// « suivant » tout court.
  final String label;

  final VoidCallback? onTap;

  static const ValueKey<String> buttonKey = ValueKey('deck-next-section');

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      key: buttonKey,
      color: colors.primary,
      borderRadius: BorderRadius.circular(FacteurRadius.small + 2),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: 0.25),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.small + 2),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                // Surtitre + nom : « suivante » dit ce que fait le bouton, le
                // nom dit où il mène. Sur une seule ligne, l'un des deux
                // sauterait à l'ellipse dès qu'une section a un nom long.
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Section suivante',
                      style: GoogleFonts.dmSans(
                        fontSize: 11,
                        height: 1.1,
                        fontWeight: FontWeight.w500,
                        color: Colors.white.withValues(alpha: 0.75),
                      ),
                    ),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.dmSans(
                        fontSize: 14,
                        height: 1.3,
                        fontWeight: FontWeight.w600,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Icon(
                PhosphorIcons.arrowRight(PhosphorIconsStyle.bold),
                size: 16,
                color: Colors.white,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
