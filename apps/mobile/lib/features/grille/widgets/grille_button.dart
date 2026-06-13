import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../grille_constants.dart';

/// Style d'un bouton de pied d'écran (`.g-btn`).
enum GrilleButtonStyle { primary, ghost, steel }

/// Bouton de pied d'écran de La Grille (`.g-btn` / `.ghost` / `.steel`).
///
/// - `primary` : plein ocre, 16 px w700, rayon `FacteurRadius.medium` (12).
/// - `ghost` : transparent, 14 px w600, texte secondaire.
/// - `steel` : plein acier (#34495e) — « Défier un·e ami·e ».
class GrilleButton extends StatelessWidget {
  const GrilleButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.style = GrilleButtonStyle.primary,
    this.icon,
  });

  final String label;
  final VoidCallback? onPressed;
  final GrilleButtonStyle style;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    final isGhost = style == GrilleButtonStyle.ghost;

    Color background;
    Color foreground;
    switch (style) {
      case GrilleButtonStyle.primary:
        background = c.primary;
        foreground = Colors.white;
      case GrilleButtonStyle.steel:
        background = GrilleConstants.steel;
        foreground = Colors.white;
      case GrilleButtonStyle.ghost:
        background = Colors.transparent;
        foreground = c.textSecondary;
    }

    return SizedBox(
      width: double.infinity,
      child: Material(
        color: background,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: InkWell(
          borderRadius: BorderRadius.circular(FacteurRadius.medium),
          onTap: onPressed,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: isGhost ? 10 : 15),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 18, color: foreground),
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    label,
                    textAlign: TextAlign.center,
                    style: FacteurTypography.bodyLarge(foreground).copyWith(
                      fontSize: isGhost ? 14 : 16,
                      fontWeight: isGhost ? FontWeight.w600 : FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
