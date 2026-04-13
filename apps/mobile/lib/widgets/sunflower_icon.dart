import 'package:flutter/material.dart';

/// Sunflower icon widget for the 🌻 recommendation feature.
///
/// Renders the native 🌻 emoji (color on all platforms) with a small
/// scale/fade animation on state change. The active state is primarily
/// conveyed by the host's background color (see the FAB in
/// `content_detail_screen.dart`), so this widget stays visually stable.
///
/// `inactiveColor` is accepted for API compatibility with the previous
/// icon-based implementation but is intentionally unused — emoji glyphs
/// keep their native colors.
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

  // Palette exposed for callers that want to theme non-icon surfaces
  // (carousel badges, page indicators, etc.).
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
      child: Text(
        '🌻',
        key: ValueKey('sunflower_${isActive ? 'active' : 'inactive'}'),
        style: TextStyle(
          fontSize: size,
          // Fixed line-height so the emoji sits cleanly centered inside
          // the FAB (orange when active, white when inactive) without
          // needing a color filter.
          height: 1.0,
        ),
      ),
    );
  }
}
