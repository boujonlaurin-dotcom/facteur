import 'package:flutter/material.dart';

import '../../../config/serein_colors.dart';

class BonnesNouvellesPill extends StatelessWidget {
  final bool isDark;
  final bool outlined;

  const BonnesNouvellesPill({
    super.key,
    required this.isDark,
    this.outlined = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: outlined
            ? Colors.transparent
            : SereinColors.sereinColor.withOpacity(isDark ? 0.18 : 0.12),
        border: outlined
            ? Border.all(color: SereinColors.sereinColor, width: 1.2)
            : null,
        borderRadius: BorderRadius.circular(12),
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
            'BONNES NOUVELLES',
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
