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

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (showIcon) ...[
          // Using new image asset logo
          Transform.translate(
            offset: Offset(
                0, size * 0.1), // Nudge down for better optical alignment
            child: Image.asset(
              'assets/icons/facteur_logo.png',
              width: size * 1.9, // Even larger relative to text
              height: size * 1.9,
              fit: BoxFit.contain,
              color: effectiveColor == context.facteurColors.textPrimary
                  ? null // Keep original colors if used on standard background
                  : effectiveColor, // Apply color override if provided
            ),
          ),
          SizedBox(width: size * 0.15), // Reduced spacing per request
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
