import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Fallback circle showing a letter initial for sources without logos.
/// Shared across keyword, topic, and source overflow chips.
class InitialCircle extends StatelessWidget {
  final String initial;
  final FacteurColors colors;
  final double size;

  const InitialCircle({
    super.key,
    required this.initial,
    required this.colors,
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: colors.textSecondary.withOpacity(0.2),
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: Text(
        initial,
        style: TextStyle(
          fontSize: size * 0.57,
          fontWeight: FontWeight.w600,
          color: Colors.white,
          height: 1,
        ),
      ),
    );
  }
}
