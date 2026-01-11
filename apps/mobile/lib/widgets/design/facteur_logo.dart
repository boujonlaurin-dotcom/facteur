import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
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
          // Using a stamp/envelope metaphor icon
          Icon(
            PhosphorIcons.envelopeOpen(PhosphorIconsStyle.fill),
            size: size * 1.2,
            color: context.facteurColors.primary,
          ),
          SizedBox(width: size * 0.4),
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
