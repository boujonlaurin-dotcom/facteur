import 'dart:math';
import 'package:google_fonts/google_fonts.dart';
import 'package:flutter/material.dart';
import 'package:facteur/config/theme.dart';

class FacteurStamp extends StatelessWidget {
  final String text;
  final bool isNew;
  final Color? color;

  const FacteurStamp({
    super.key,
    required this.text,
    this.isNew = false,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    // Generate a consistent pseudo-random rotation based on the text hash
    // This ensures the same stamp always has the same "imperfect" angle
    // Range: -2 to +2 degrees
    final int hash = text.hashCode;
    final Random random = Random(hash);
    final double rotationDegrees = -2.0 + random.nextDouble() * 4.0;
    final double rotationRadians = rotationDegrees * (pi / 180);

    final stampColor = color ??
        (isNew
            ? context.facteurColors.primary
            : context.facteurColors
                .textSecondary); // Assuming textStamp maps to textSecondary or similar if no textStamp exists in colors scheme

    // "Ink" opacity effect if not new
    final Color effectiveColor =
        isNew ? stampColor : stampColor.withValues(alpha: 0.7);

    return Transform.rotate(
      angle: rotationRadians,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space2,
          vertical: 2, // Tighter vertical padding for "stamp" look
        ),
        decoration: BoxDecoration(
          border: Border.all(
            color: effectiveColor,
            width: 1.5,
          ),
          borderRadius: BorderRadius.circular(
              4), // Slightly rounded corners, but mostly sharp
          color: isNew
              ? effectiveColor.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Text(
          text.toUpperCase(),
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                // Using labelSmall as stamp fallback if stamp style not in theme, or define it. FacteurTypography.stamp was distinctive. Let's use it from context if possible, but standard TextTheme doesn't have 'stamp'.
                // Wait, I can keep using GoogleFonts.courierPrime directly here if needed, or map it.
                // Let's check config/theme.dart again if 'stamp' is there. It is static method.
                // I'll stick to manual style here to replicate 'stamp' style but color context aware.
                fontFamily: GoogleFonts.courierPrime().fontFamily,
                fontSize: 11,
                fontWeight: FontWeight.w700,
                height: 1.2,
                letterSpacing: 0.5,
                color: effectiveColor,
              ),
        ),
      ),
    );
  }
}
