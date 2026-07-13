import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../config/theme.dart';

/// Surface flottante « liquid glass » réutilisable — pattern extrait de
/// `MainBottomNav` : ombre douce posée hors du clip → coins arrondis →
/// blur conditionnel → fond translucide + hairline.
///
/// [enableBlur] à `false` (web, chrome au-dessus d'une platform view type
/// WebView Android) rend le même pill avec un fond quasi-opaque et sans
/// `BackdropFilter` : un BackdropFilter ne peut pas échantillonner une
/// platform view, et l'animer force une re-rasterisation du flou à chaque
/// frame sur le web (CanvasKit).
class GlassPill extends StatelessWidget {
  final Widget child;
  final BorderRadius borderRadius;
  final bool enableBlur;

  /// Direction de l'ombre : (0, 4) pour un header, (0, -4) pour un footer.
  final Offset shadowOffset;

  const GlassPill({
    super.key,
    required this.child,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.enableBlur = true,
    this.shadowOffset = const Offset(0, 4),
  });

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    // Fond translucide dérivé du token de thème (dark et light) ; seul l'alpha
    // diffère (plus opaque sans blur pour rester lisible au-dessus d'une
    // platform view).
    final fillColor = context.facteurColors.backgroundPrimary.withValues(
      alpha: isDark ? (enableBlur ? 0.80 : 0.97) : (enableBlur ? 0.86 : 0.98),
    );
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : const Color.fromRGBO(0, 0, 0, 0.08);

    final content = Container(
      decoration: BoxDecoration(
        color: fillColor,
        borderRadius: borderRadius,
        border: Border.all(color: borderColor),
      ),
      child: child,
    );

    return DecoratedBox(
      // Ombre douce pour décoller le pill du contenu — hors du ClipRRect,
      // sinon elle serait rognée.
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
        child: enableBlur
            ? BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                child: content,
              )
            : content,
      ),
    );
  }
}
