import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';

class FacteurLogo extends StatelessWidget {
  final double size;
  final bool showIcon;
  final bool showText;
  final Color? color;

  const FacteurLogo({
    super.key,
    this.size = 24.0,
    this.showIcon = true,
    this.showText = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.facteurColors.textPrimary;
    final colors = context.facteurColors;
    // Logo officiel (SVG vectoriel), pas la variante app-icon. Le PNG
    // `fallbackLogoPath` sert de repli errorBuilder pour la branche bitmap.
    const logoPath = 'assets/icons/logo_officiel.svg';
    const fallbackLogoPath = 'assets/icons/facteur_logo.png';
    final logoSize = size * 1.7;

    // [filterColor] n'est passé que lorsqu'un `color` custom est demandé
    // (effectiveColor != textPrimary) ; par défaut, aucun filtre → le logo
    // officiel est rendu dans ses vraies couleurs.
    Widget buildLogoImage(String path, [Color? filterColor]) {
      final colorFilter = filterColor != null
          ? ColorFilter.mode(filterColor, BlendMode.srcIn)
          : null;

      if (path.endsWith('.svg')) {
        return SvgPicture.asset(
          path,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          colorFilter: colorFilter,
          placeholderBuilder: (_) =>
              SizedBox(width: logoSize, height: logoSize),
        );
      }

      final img = Image.asset(
        path,
        width: logoSize,
        height: logoSize,
        fit: BoxFit.contain,
        isAntiAlias: true,
        filterQuality: FilterQuality.high,
        errorBuilder: (_, __, ___) => Image.asset(
          fallbackLogoPath,
          width: logoSize,
          height: logoSize,
          fit: BoxFit.contain,
          isAntiAlias: true,
          filterQuality: FilterQuality.high,
        ),
      );
      if (colorFilter != null) {
        return ColorFiltered(colorFilter: colorFilter, child: img);
      }
      return img;
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showIcon) ...[
          Transform.translate(
            offset: Offset(0, size * 0.06), // Reduced vertical offset
            child: buildLogoImage(
              logoPath,
              effectiveColor == colors.textPrimary ? null : effectiveColor,
            ),
          ),
          if (showText) SizedBox(width: size * 0.06),
        ],
        if (showText)
          Text(
            'Facteur',
            style: GoogleFonts.fraunces(
              fontSize: size,
              fontWeight: FontWeight.w700,
              color: effectiveColor,
              letterSpacing: -0.5,
            ),
          ),
      ],
    );
  }
}
