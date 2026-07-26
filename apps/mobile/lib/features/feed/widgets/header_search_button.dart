import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../providers/feed_provider.dart';
import '../providers/search_navigation_provider.dart';
import 'search_filter_sheet.dart';

/// Loupe du header partagé — point d'entrée unique de la recherche universelle
/// (story 30.1). Cible de 40 px (contre 34×34 pour l'ancienne loupe noyée dans
/// la barre de filtres de Flâner) et présente sur les deux onglets.
///
/// Icône simple quel que soit l'état du filtre : la barre de filtres de Flâner
/// (`_SearchTrigger` dans `FeedFilterBar`) porte déjà sa propre pill d'état, la
/// dupliquer ici faisait chevaucher le logo « Facteur » du header (Stack
/// centré). Sur L'Essentiel (qui ne monte pas `FeedFilterBar`), effacer un
/// filtre reste possible depuis la sheet (« Effacer le filtre »).
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
    final keyword = ref.watch(feedFilterSelectionProvider).keyword;

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

    return Semantics(
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
    );
  }
}
