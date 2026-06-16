import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
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
enum ComposeTourneeButtonStyle { primary, secondary }

class ComposeTourneeButton extends StatelessWidget {
  const ComposeTourneeButton({
    super.key,
    this.padding,
    this.style = ComposeTourneeButtonStyle.primary,
  });

  final EdgeInsetsGeometry? padding;
  final ComposeTourneeButtonStyle style;

  void _open(BuildContext context) {
    HapticFeedback.mediumImpact();
    showTourneeComposerSheet(context);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: padding ?? EdgeInsets.zero,
      child: style == ComposeTourneeButtonStyle.primary
          ? PrimaryButton(
              label: 'Composer ma Tournée',
              icon: PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.bold),
              onPressed: () => _open(context),
            )
          : SizedBox(
              width: double.infinity,
              height: 52,
              child: OutlinedButton.icon(
                onPressed: () => _open(context),
                icon: Icon(
                  PhosphorIcons.slidersHorizontal(
                    PhosphorIconsStyle.regular,
                  ),
                ),
                label: const Text('Composer ma Tournée'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: context.facteurColors.textPrimary,
                  side: BorderSide(color: context.facteurColors.border),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FacteurRadius.small),
                  ),
                ),
              ),
            ),
    );
  }
}
