import 'package:flutter/material.dart';

import '../../config/serein_colors.dart';

/// Subtle mode indicator rendered at the top of Feed and Digest screens.
///
/// Renders a thin accent line (1.5px) + a soft radial halo (40px) that
/// communicates the active mode (Normal = warm orange, Serein = calm green)
/// without adding any layout space. Wrap in [IgnorePointer] + [Positioned].
class ModeAccent extends StatelessWidget {
  const ModeAccent({super.key, required this.isSerein});

  final bool isSerein;

  static const _transitionDuration = Duration(milliseconds: 400);
  static const _curve = Curves.easeInOut;

  @override
  Widget build(BuildContext context) {
    final color =
        isSerein ? SereinColors.sereinColor : SereinColors.normalColor;
    final haloOpacity = isSerein ? 0.10 : 0.13;

    return IgnorePointer(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Accent line (1.5px) ──────────────────────────
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(end: color),
            duration: _transitionDuration,
            curve: _curve,
            builder: (context, value, _) => Container(
              height: 1.5,
              color: value?.withValues(alpha: 0.7),
            ),
          ),

          // ── Linear halo — full-width top-to-bottom fade ──
          TweenAnimationBuilder<Color?>(
            tween: ColorTween(
              end: color.withValues(alpha: haloOpacity),
            ),
            duration: _transitionDuration,
            curve: _curve,
            builder: (context, value, _) {
              final c = value ?? Colors.transparent;
              return Container(
                height: 30,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      c,
                      c.withValues(alpha: c.a * 0.4),
                      Colors.transparent,
                    ],
                    stops: const [0.0, 0.5, 1.0],
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }
}
