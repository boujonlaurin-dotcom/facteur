import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../providers/active_filter_label_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/search_navigation_provider.dart';
import 'search_filter_sheet.dart';

/// Loupe du header partagé — point d'entrée unique de la recherche universelle
/// (story 30.1). Cible de 40 px (contre 34×34 pour l'ancienne loupe noyée dans
/// la barre de filtres de Flâner) et présente sur les deux onglets.
///
/// Vit dans `features/feed/` et non dans le shell : le shell compose le header,
/// il n'a pas à connaître l'état de filtrage du feed — même découpage que
/// [ProfileAvatarButton].
class HeaderSearchButton extends ConsumerWidget {
  /// Onglet qui héberge le bouton. Détermine si valider une recherche doit
  /// basculer sur Flâner : c'est là, et seulement là, que le flux filtré se lit.
  final bool isEssentielTab;

  const HeaderSearchButton({super.key, required this.isEssentielTab});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    // Le mot-clé sert à préremplir la sheet ; l'état actif de la loupe suit
    // désormais **n'importe quelle** dimension de filtre via ce provider dérivé.
    final keyword = ref.watch(feedFilterSelectionProvider).keyword;
    final active = ref.watch(activeFilterLabelProvider);

    void openSheet() {
      HapticFeedback.mediumImpact();
      SearchFilterSheet.show(
        context,
        currentKeyword: keyword,
        origin: kSearchOriginHeader,
        tab: isEssentielTab ? kSearchTabEssentiel : kSearchTabFlaner,
        onApplied: isEssentielTab
            ? () {
                // Arme le bandeau contextuel *avant* de basculer : Flâner le lit
                // au montage. Effacer un filtre ne passe pas par `onApplied`,
                // donc pas de bandeau parasite sur un « non ».
                ref.read(searchJustNavigatedProvider.notifier).state = true;
                GoRouter.of(context).go(RoutePaths.flaner);
              }
            : null,
      );
    }

    // Bascule animée icône ↔ pill (~200 ms) : l'expansion de la loupe en pill
    // filtre doit être lisible, comme l'animation de branche du shell.
    return AnimatedSize(
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.centerRight,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        switchInCurve: Curves.easeOutCubic,
        switchOutCurve: Curves.easeOutCubic,
        child: active == null
            ? Semantics(
                key: const ValueKey('search-icon'),
                button: true,
                label: 'Rechercher',
                child: InkResponse(
                  radius: 22,
                  onTap: openSheet,
                  child: SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(
                      PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                      size: 22,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              )
            : _ActiveFilterPill(
                key: const ValueKey('search-pill'),
                label: active.label,
                colors: colors,
                onTapLabel: openSheet,
                onClear: () {
                  HapticFeedback.mediumImpact();
                  // Un seul geste efface n'importe quel filtre (mot-clé, source,
                  // thème, sujet). `clearFilters` ne navigue pas : effacer
                  // n'est pas appliquer — on ne téléporte pas l'utilisateur pour
                  // avoir dit « non ».
                  ref.read(feedProvider.notifier).clearFilters();
                },
              ),
      ),
    );
  }
}

/// Pill « filtre actif » du header : label tronqué + croix de sortie. Rappelle
/// qu'un filtre est en cours même quand la barre de filtres est hors écran (ou
/// absente, comme sur L'Essentiel), et l'annuler ne demande plus d'ouvrir la
/// sheet.
class _ActiveFilterPill extends StatelessWidget {
  final String label;
  final FacteurColors colors;
  final VoidCallback onTapLabel;
  final VoidCallback onClear;

  const _ActiveFilterPill({
    super.key,
    required this.label,
    required this.colors,
    required this.onTapLabel,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: Center(
        child: Container(
          height: 34,
          padding: const EdgeInsets.only(left: 9, right: 3),
          decoration: BoxDecoration(
            color: colors.primary.withValues(alpha: 0.12),
            border: Border.all(color: colors.primary),
            borderRadius: BorderRadius.circular(FacteurRadius.full),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                button: true,
                label: 'Rechercher',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTapLabel,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
                          size: 18,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 5),
                        ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 130),
                          child: Text(
                            label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              Semantics(
                button: true,
                label: 'Effacer le filtre',
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                    child: _ClearIcon(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearIcon extends StatelessWidget {
  const _ClearIcon();

  @override
  Widget build(BuildContext context) {
    return Icon(
      PhosphorIcons.x(PhosphorIconsStyle.bold),
      size: 12,
      color: context.facteurColors.primary,
    );
  }
}
