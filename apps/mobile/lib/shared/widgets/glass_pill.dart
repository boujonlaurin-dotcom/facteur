import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Surface flottante « verre » réutilisable — pattern extrait de
/// `MainBottomNav` : ombre douce posée hors du clip → coins arrondis → fond
/// quasi-opaque → **double liseré « verre »** (arête extérieure sombre + liseré
/// intérieur clair, effet biseau / épaisseur de verre).
///
/// Aucun `BackdropFilter` : le rebord est **100 % statique** (calculé au build),
/// donc zéro re-rasterisation par frame ⇒ scroll intact — priorité absolue.
/// Le fond quasi-opaque masque le corps de l'article et ne laisse passer le
/// contenu qu'aux encoches des coins arrondis.
class GlassPill extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;

  /// Direction de l'ombre : (0, 4) pour un header, (0, -4) pour un footer.
  final Offset shadowOffset;

  const GlassPill({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.shadowOffset = const Offset(0, 4),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    // Fond quasi-opaque dérivé du token de thème : masque le corps du pill,
    // ne laisse « passer » le contenu qu'aux coins arrondis.
    final fillColor = context.facteurColors.backgroundPrimary.withValues(
      alpha: isDark ? 0.97 : 0.98,
    );
    // Arête extérieure sombre (hairline discret, proche de l'existant).
    final outerEdge = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color.fromRGBO(0, 0, 0, 0.10);
    // Liseré intérieur clair : effet « épaisseur de verre » / biseau. Peint 1px
    // à l'intérieur de l'arête sombre (via le padding), discret.
    final innerEdge = isDark
        ? Colors.white.withValues(alpha: 0.07)
        : Colors.white.withValues(alpha: 0.60);

    return DecoratedBox(
      // Ombre douce pour décoller le pill du contenu — hors du ClipRRect,
      // sinon elle serait rognée par les coins arrondis.
      decoration: BoxDecoration(
        borderRadius: borderRadius,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.32 : 0.10),
            blurRadius: 18,
            spreadRadius: -6,
            offset: shadowOffset,
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: borderRadius,
        child: DecoratedBox(
          // Fond + arête extérieure sombre.
          decoration: BoxDecoration(
            color: fillColor,
            borderRadius: borderRadius,
            border: Border.all(color: outerEdge),
          ),
          // 1px d'écart → le fond apparaît entre les deux liserés.
          child: Padding(
            padding: const EdgeInsets.all(1),
            child: DecoratedBox(
              // Liseré intérieur clair (biseau). Statique, aucun coût par frame.
              decoration: BoxDecoration(
                borderRadius: borderRadius,
                border: Border.all(color: innerEdge),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}
