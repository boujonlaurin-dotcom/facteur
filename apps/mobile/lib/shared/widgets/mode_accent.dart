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
    // Normal mode: nothing visible. Serein mode: thin accent line only.
    if (!isSerein) {
      return const IgnorePointer(child: SizedBox.shrink());
    }

    return IgnorePointer(
      child: TweenAnimationBuilder<Color?>(
        tween: ColorTween(end: SereinColors.sereinColor),
        duration: _transitionDuration,
        curve: _curve,
        builder: (context, value, _) => Container(
          height: 1.5,
          color: value?.withValues(alpha: 0.7),
        ),
      ),
    );
  }
}
