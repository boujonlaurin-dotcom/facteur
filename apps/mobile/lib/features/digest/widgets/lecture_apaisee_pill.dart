import 'package:flutter/material.dart';

import '../../../config/serein_colors.dart';

class LectureApaiseePill extends StatelessWidget {
  final bool isDark;

  const LectureApaiseePill({
    super.key,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: SereinColors.sereinColor.withOpacity(isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            SereinColors.sereinIcon,
            size: 12,
            color: SereinColors.sereinColor,
          ),
          const SizedBox(width: 5),
          const Text(
            'LECTURE APAISÉE',
            style: TextStyle(
              color: SereinColors.sereinColor,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}
