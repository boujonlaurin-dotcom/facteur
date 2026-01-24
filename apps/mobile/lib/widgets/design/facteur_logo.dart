import 'package:flutter/foundation.dart';
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
    final colors = context.facteurColors;
    // Detect current theme brightness to choose the right logo
    final brightness = Theme.of(context).brightness;
    final isDark = brightness == Brightness.dark;
    const androidSafeLogoPath = 'assets/icons/logo_facteur_app_icon.png';
    final logoPath = !kIsWeb && defaultTargetPlatform == TargetPlatform.android
        ? androidSafeLogoPath
        : (isDark
            ? 'assets/icons/logo facteur fond_sombre.png'
            : 'assets/icons/logo facteur fond_clair.png');
    const fallbackLogoPath = 'assets/icons/facteur_logo.png';
    final logoSize = size * 1.7;

    Widget buildLogoImage(String path) {
      return Image.asset(
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
    }

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showIcon) ...[
          // Using theme-appropriate logo (dark/light)
          Transform.translate(
            offset: Offset(
                0, size * 0.06), // Reduced vertical offset
            child: effectiveColor == colors.textPrimary
                ? buildLogoImage(logoPath)
                : ColorFiltered(
                    colorFilter: ColorFilter.mode(
                      effectiveColor,
                      BlendMode.srcIn, // Preserves transparency while applying color
                    ),
                    child: buildLogoImage(logoPath),
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
