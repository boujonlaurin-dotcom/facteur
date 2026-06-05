import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import 'manage_favorites_sheet.dart';

/// Shim historique (Story 10.2) — « Composer ma Tournée » ouvre désormais la
/// sheet unifiée [showManageFavoritesSheet] côté Essentiel. Conservé pour ne pas
/// toucher les ~appels existants (section_block, flux_continu_screen, boutons).
Future<void> showTourneeComposerSheet(BuildContext context) {
  return showManageFavoritesSheet(
    context,
    entry: ManageFavoritesEntry.essentiel,
  );
}

/// Bouton « Composer ma Tournée » — point d'entrée vers la sheet unifiée.
class ComposeTourneeButton extends StatelessWidget {
  const ComposeTourneeButton({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () {
            HapticFeedback.mediumImpact();
            showTourneeComposerSheet(context);
          },
          icon: Icon(
            PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.bold),
            size: 16,
            color: colors.primary,
          ),
          label: Text(
            'Composer ma Tournée',
            style: TextStyle(
              color: colors.primary,
              fontWeight: FontWeight.w600,
              fontSize: 14,
            ),
          ),
          style: OutlinedButton.styleFrom(
            side: BorderSide(color: colors.primary.withValues(alpha: 0.5)),
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
            ),
          ),
        ),
      ),
    );
  }
}
