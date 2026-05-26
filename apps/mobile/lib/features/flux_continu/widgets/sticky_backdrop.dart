import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Parchment-tinted backdrop shared by every sticky overlay on the Flux Continu
/// screen — the editorial [StickyTabBar] and the Explorer sticky in
/// `flux_continu_screen.dart`. Keeping the shell in one place locks the two
/// surfaces to identical blur, colour, border and shadow so the cross-fade
/// between them feels like one bar morphing rather than two distinct bars.
///
/// Adapts to dark mode: parchment overlay in light, dark-surface tint in dark.
class StickyBackdrop extends StatelessWidget {
  final Widget child;

  const StickyBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final isDark = context.isDarkMode;
    final backdropColor = isDark
        ? context.facteurColors.backgroundPrimary.withValues(alpha: 0.92)
        : const Color.fromRGBO(242, 232, 213, 0.92);
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color.fromRGBO(0, 0, 0, 0.06);

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: backdropColor,
            border: Border(
              bottom: BorderSide(color: borderColor, width: 1),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                spreadRadius: -6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(bottom: false, child: child),
        ),
      ),
    );
  }
}
