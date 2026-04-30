import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';

class EssentielPill extends StatelessWidget {
  final FacteurColors colors;
  final bool isDark;

  const EssentielPill({
    super.key,
    required this.colors,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(isDark ? 0.18 : 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            PhosphorIcons.envelope(PhosphorIconsStyle.fill),
            size: 12,
            color: colors.primary,
          ),
          const SizedBox(width: 5),
          Text(
            "L'ESSENTIEL",
            style: TextStyle(
              color: colors.primary,
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

const List<String> _frMonthsAbbr = [
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

String formatDigestDate(DateTime date) {
  return '${date.day} ${_frMonthsAbbr[date.month - 1]}';
}
