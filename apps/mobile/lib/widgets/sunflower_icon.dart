import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// Sunflower icon widget for the 🌻 recommendation feature.
///
/// Two states:
/// - **Inactive**: monochrome outline icon, same style as other icons
/// - **Active**: colorful sunflower (yellow/green/brown) with animation
///
/// The transition uses an AnimatedSwitcher with a scale+fade effect (~300ms).
class SunflowerIcon extends StatelessWidget {
  final bool isActive;
  final double size;
  final Color? inactiveColor;

  const SunflowerIcon({
    super.key,
    required this.isActive,
    this.size = 25,
    this.inactiveColor,
  });

  // Sunflower colors
  static const Color sunflowerYellow = Color(0xFFFFC107);
  static const Color sunflowerGreen = Color(0xFF4CAF50);
  static const Color sunflowerBrown = Color(0xFF795548);

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 300),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) {
        return ScaleTransition(
          scale: animation,
          child: FadeTransition(
            opacity: animation,
            child: child,
          ),
        );
      },
      child: isActive
          ? ShaderMask(
              key: const ValueKey('active'),
              shaderCallback: (bounds) => const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [sunflowerYellow, sunflowerBrown],
                stops: [0.3, 1.0],
              ).createShader(bounds),
              blendMode: BlendMode.srcIn,
              child: Icon(
                PhosphorIcons.flowerTulip(PhosphorIconsStyle.fill),
                size: size,
                color: Colors.white, // Will be replaced by shader
              ),
            )
          : Icon(
              key: const ValueKey('inactive'),
              PhosphorIcons.flowerTulip(PhosphorIconsStyle.regular),
              size: size,
              color: inactiveColor,
            ),
    );
  }
}
