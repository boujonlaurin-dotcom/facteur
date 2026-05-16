import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Parchment-tinted backdrop shared by every sticky overlay on the Flux Continu
/// screen — the editorial [StickyTabBar] and the Explorer sticky in
/// `flux_continu_screen.dart`. Keeping the shell in one place locks the two
/// surfaces to identical blur, colour, border and shadow so the cross-fade
/// between them feels like one bar morphing rather than two distinct bars.
class StickyBackdrop extends StatelessWidget {
  final Widget child;

  const StickyBackdrop({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color.fromRGBO(242, 232, 213, 0.92),
            border: const Border(
              bottom: BorderSide(
                color: Color.fromRGBO(0, 0, 0, 0.06),
                width: 1,
              ),
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
