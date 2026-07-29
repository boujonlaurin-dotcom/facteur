import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Ligne de soutien affichée sous les bénéfices, juste au-dessus du CTA.
///
/// L'offre est passée à un cadrage « soutien » sans montant chiffré (le prix
/// libre arrivera avec la refonte billing). Ce widget ne rend donc plus que la
/// note d'accompagnement, dans la même veine typographique que le reste de
/// l'écran (design-system-first, aucun nombre en Fraunces 36).
class PriceRow extends StatelessWidget {
  const PriceRow({super.key, required this.note});

  final String note;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Text(
      note,
      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
    );
  }
}
