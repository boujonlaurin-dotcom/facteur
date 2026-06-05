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
        // Tuile teintée douce : fond primary léger + ombre subtile pour la
        // détacher du fond crème, plus grande et plus visible que le contour.
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            boxShadow: [
              BoxShadow(
                color: colors.primary.withValues(alpha: 0.18),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: colors.primary.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () {
                HapticFeedback.mediumImpact();
                showTourneeComposerSheet(context);
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.bold),
                      size: 18,
                      color: colors.primary,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Composer ma Tournée',
                      style: TextStyle(
                        color: colors.primary,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
