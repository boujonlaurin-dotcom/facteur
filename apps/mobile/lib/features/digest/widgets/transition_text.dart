import 'package:flutter/material.dart';
import '../../../config/theme.dart';

/// Editorial transition text between topic sections (N2).
/// Italic bridging sentence with separator lines above and below.
class TransitionText extends StatelessWidget {
  final String text;

  const TransitionText({super.key, required this.text});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24),
      child: Column(
        children: [
          // Top separator
          Container(
            height: 1,
            color: colors.textTertiary.withValues(alpha: 0.2),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Text(
              text,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w400,
                fontStyle: FontStyle.italic,
                color: colors.textSecondary,
              ),
            ),
          ),
          // Bottom separator
          Container(
            height: 1,
            color: colors.textTertiary.withValues(alpha: 0.2),
          ),
        ],
      ),
    );
  }
}
