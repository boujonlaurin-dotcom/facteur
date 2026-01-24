import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';

class FacteurLogo extends StatelessWidget {
  final double size;
  final bool showIcon;
  final Color? color;

  const FacteurLogo({
    super.key,
    this.size = 24.0,
    this.showIcon = true,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveColor = color ?? context.facteurColors.textPrimary;
    // Detect current theme brightness to choose the right logo
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    final logoPath = isDark
        ? 'assets/icons/logo facteur fond_sombre.png'
        : 'assets/icons/logo facteur fond_clair.png';

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showIcon) ...[
          // Using theme-appropriate logo (dark/light)
          Transform.translate(
            offset: Offset(
                0, size * 0.06), // Reduced vertical offset
            child: effectiveColor == context.facteurColors.textPrimary
                ? Image.asset(
                    logoPath,
                    width: size * 1.7, // Reduced logo size
                    height: size * 1.7,
                    fit: BoxFit.contain,
                    isAntiAlias: true,
                    filterQuality: FilterQuality.high,
                    // No color parameter = preserves original colors
                  )
                : ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      effectiveColor,
                      BlendMode.srcIn, // Preserves transparency while applying color
                    ),
                    child: Image.asset(
                      logoPath,
                      width: size * 1.45,
                      height: size * 1.45,
                      fit: BoxFit.contain,
                      isAntiAlias: true,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
          ),
          SizedBox(width: size * 0.06), // Tight spacing between logo and text
        ],
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
