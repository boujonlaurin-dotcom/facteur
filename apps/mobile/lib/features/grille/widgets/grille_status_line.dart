import 'package:flutter/material.dart';

import '../../../config/theme.dart';

/// Ligne de statut sous la grille (`.mot-status`) — message d'aide ou d'erreur.
class GrilleStatusLine extends StatelessWidget {
  const GrilleStatusLine({
    super.key,
    required this.message,
    this.isError = false,
  });

  final String message;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final c = context.facteurColors;
    return SizedBox(
      height: 26,
      child: Center(
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: FacteurTypography.bodySmall(
            isError ? c.error : c.textTertiary,
          ).copyWith(fontSize: 12.5),
        ),
      ),
    );
  }
}
