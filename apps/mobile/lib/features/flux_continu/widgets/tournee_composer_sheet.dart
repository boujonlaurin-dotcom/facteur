import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../shared/widgets/buttons/primary_button.dart';
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
///
/// Style canonique [PrimaryButton] (terracotta plein, `elevation:0`,
/// `FacteurRadius.small`) au lieu de l'ancienne tuile teintée + ombre, perçue
/// comme un « dégradé étrange » hors design-system. L'haptique est conservée.
class ComposeTourneeButton extends StatelessWidget {
  const ComposeTourneeButton({super.key, this.padding});

  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: PrimaryButton(
        label: 'Composer ma Tournée',
        icon: PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.bold),
        onPressed: () {
          HapticFeedback.mediumImpact();
          showTourneeComposerSheet(context);
        },
      ),
    );
  }
}
