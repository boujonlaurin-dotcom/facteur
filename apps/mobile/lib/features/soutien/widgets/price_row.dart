import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../soutien_copy.dart';

/// « 3 € /mois » + note d'accompagnement (« moins qu'un café… » ou
/// « sans engagement… » selon la surface).
class PriceRow extends StatelessWidget {
  const PriceRow({super.key, required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          SoutienCopy.priceAmount,
          style: GoogleFonts.fraunces(
            fontSize: 36,
            fontWeight: FontWeight.w700,
            height: 1.0,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: 4),
        Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text(
            SoutienCopy.priceSuffix,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(
              note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ),
        ),
      ],
    );
  }
}
