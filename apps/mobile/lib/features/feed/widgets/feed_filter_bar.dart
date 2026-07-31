import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/active_filter_label_provider.dart';
import '../providers/feed_provider.dart';
import '../providers/tab_counts_provider.dart';
import 'favorite_topic_tabs.dart';
import 'pin_subjects_sheet.dart';
import 'search_filter_sheet.dart';

/// Barre de filtres sticky de Flâner (et de la zone Explorer du Flux Continu) :
/// les onglets favoris qui défilent, la pill de recherche active, et
/// l'affordance « gérer mes onglets » épinglée à droite. Pilote `feedProvider`
/// directement — un changement de filtre se propage à tout écran qui l'observe.
///
/// Le filtrage par source / sujet / thème / mot-clé passe désormais par la
/// recherche universelle du header (story 30.1) : l'entonnoir et sa rangée de
/// chips dépliables ont été retirés, ils faisaient double emploi.
class FeedFilterBar extends ConsumerWidget {
  final VoidCallback? onAfterChange;

  const FeedFilterBar({
    super.key,
    this.onAfterChange,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(feedProvider.notifier);
    final selection = ref.watch(feedFilterSelectionProvider);
    // Même source de vérité que la loupe du header : la pill n'apparaît que pour
    // un filtre mot-clé (tapper = rouvrir la sheet pour l'affiner) ; les filtres
    // source/thème/sujet sont déjà matérialisés par l'onglet favori actif.
    final active = ref.watch(activeFilterLabelProvider);
    final keywordActive = active != null && active.isKeyword;
    final feedItems =
        ref.watch(feedProvider).valueOrNull?.items ?? const <dynamic>[];
    final serverCounts = ref.watch(tabCountsProvider).valueOrNull;
    return FavoriteTopicTabs(
      items: feedItems.cast(),
      serverCounts: serverCounts,
      selectedTopicSlug: selection.topic,
      selectedThemeSlug: selection.theme,
      selectedEntitySlug: selection.entity,
      selectedSourceId: selection.sourceId,
      onTabTap: (kind, slug) async {
        switch (kind) {
          case FavoriteTabKind.subjectTopic:
            await notifier.setTopic(slug);
            break;
          case FavoriteTabKind.subjectEntity:
            await notifier.setEntity(slug);
            break;
          case FavoriteTabKind.theme:
            await notifier.setTheme(slug);
            break;
          case FavoriteTabKind.source:
            await notifier.setSource(slug);
            break;
        }
        onAfterChange?.call();
      },
      // Taper l'onglet actif vide toute la sélection (feed non filtré).
      // `clearFilters()` porte la liste des dimensions côté notifier : c'est
      // l'oubli de `setSource(null)` ici qui avait motivé le regroupement.
      onTapActiveTab: () async {
        await HapticFeedback.selectionClick();
        await notifier.clearFilters();
        onAfterChange?.call();
      },
      // Le « + » (ou l'engrenage) épingle des sujets précis (custom topics) —
      // le filtrage par thème/source/mot-clé passe par la recherche du header.
      onAddFavorite: () {
        HapticFeedback.mediumImpact();
        showPinSubjectsSheet(context);
      },
      // Story 30.1 — le point d'entrée de la recherche vit dans le header
      // partagé (visible sur les deux onglets). Cette pill n'est qu'un
      // **affichage d'état** : « 🔍 mot-clé ✕ » quand une recherche est active,
      // rien du tout sinon.
      trailing: keywordActive
          ? _SearchTrigger(
              label: active.label,
              onTap: () {
                HapticFeedback.mediumImpact();
                SearchFilterSheet.show(
                  context,
                  currentKeyword: selection.keyword,
                  origin: kSearchOriginFilterBar,
                  onApplied: onAfterChange,
                );
              },
              onClear: () async {
                await HapticFeedback.mediumImpact();
                await notifier.clearFilters();
                onAfterChange?.call();
              },
            )
          : null,
    );
  }
}

/// Pill d'état de la recherche active : « 🔍 mot-clé ✕ ». Tap = rouvrir la
/// sheet pour affiner, ✕ = effacer le filtre. N'est monté que lorsqu'une
/// recherche est en cours (story 30.1) — l'entrée de la recherche vit
/// désormais dans le header partagé.
///
/// [label] provient de `activeFilterLabelProvider` (même source que le header).
class _SearchTrigger extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClear;

  const _SearchTrigger({
    required this.label,
    required this.onTap,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final primary = context.facteurColors.primary;
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 34,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: primary.withValues(alpha: 0.12),
          border: Border.all(color: primary),
          borderRadius: BorderRadius.circular(FacteurRadius.full),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.magnifyingGlass(PhosphorIconsStyle.bold),
              size: 14,
              color: primary,
            ),
            const SizedBox(width: 5),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w600,
                  color: primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 7,
                ),
                child: Icon(
                  PhosphorIcons.x(PhosphorIconsStyle.bold),
                  size: 12,
                  color: primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
