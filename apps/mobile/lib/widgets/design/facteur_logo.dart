import 'package:flutter/material.dart';
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
    const logoPath = 'assets/icons/logo_facteur_ui.png';
    const fallbackLogoPath = 'assets/icons/logo_facteur_ui.png';
    final logoSize = size * 1.7;

    Widget buildLogoImage(String path, [Color? filterColor]) {
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
      if (filterColor != null) {
        return ColorFiltered(
          colorFilter: ColorFilter.mode(filterColor, BlendMode.srcIn),
          child: img,
        );
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
