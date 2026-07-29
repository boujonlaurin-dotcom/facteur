/// Persistance partagée d'un réordre de la Tournée du jour.
///
/// Deux points d'entrée utilisateur produisent le **même** effet : la sheet
/// « Composer ma Tournée » (`manage_favorites_sheet.dart`) et le drag des
/// onglets du header sticky (`flux_continu_screen.dart`). Ce fichier porte la
/// séquence canonique — garde d'appartenance → `markCustomized()` →
/// `setOrder(mergeVisibleReorder(...))` → sync serveur thèmes/sources — pour
/// qu'aucun des deux chemins ne dérive de l'autre.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../feed/providers/tab_order_prefs_provider.dart'
    show mergeVisibleReorder;
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import 'tournee_order_prefs_provider.dart' hide applyOrder;

/// Remappe un réordre d'onglets du header vers la nouvelle séquence des clés
/// d'ordre. [orderKeys] est la liste des `StickyTab.orderKey` dans l'ordre
/// affiché (`null` = onglet figé) ; [oldIndex]/[newIndex] sont les index bruts
/// de `ReorderableListView` (`newIndex` exprimé dans l'espace d'insertion,
/// c.-à-d. avant retrait de l'élément déplacé).
///
/// La cible est **clampée** entre le premier et le dernier emplacement
/// réordonnable : le héros Essentiel reste infranchissable en tête, Citation et
/// Fin de tournée en queue. Les onglets figés *intérieurs* (Mot du jour,
/// « Pour toi ») peuvent être traversés — ils se ré-épinglent à leur slot au
/// rebuild suivant.
///
/// Retourne `null` quand le mouvement est impossible ou sans effet (onglet figé
/// saisi, index hors bornes, moins de deux onglets déplaçables, position
/// inchangée) — l'appelant ne doit alors rien persister.
List<String>? reorderTourneeTabKeys(
  List<String?> orderKeys,
  int oldIndex,
  int newIndex,
) {
  if (oldIndex < 0 || oldIndex >= orderKeys.length) return null;
  if (orderKeys[oldIndex] == null) return null;

  final moved = orderKeys[oldIndex];
  final rest = [...orderKeys]..removeAt(oldIndex);
  // Bornes d'insertion dans `rest` : après le préfixe figé, avant le suffixe
  // figé. Calculées post-retrait pour rester valides quel que soit oldIndex.
  var lo = 0;
  while (lo < rest.length && rest[lo] == null) {
    lo++;
  }
  var hi = rest.length;
  while (hi > lo && rest[hi - 1] == null) {
    hi--;
  }
  if (lo >= hi) return null; // aucun autre onglet déplaçable.

  final target = (newIndex > oldIndex ? newIndex - 1 : newIndex).clamp(lo, hi);
  if (target == oldIndex) return null;
  rest.insert(target, moved);
  return [
    for (final k in rest)
      if (k != null) k,
  ];
}

/// Garde-fou des réordres : ne pas réécrire l'ordre tant que les données
/// d'appartenance (intérêts + sources) ne sont pas chargées — sinon un favori
/// non matérialisé serait élagué de l'ordre (cf. `mergeVisibleReorder`).
bool tourneeMembershipDataReady(WidgetRef ref) =>
    ref.read(userInterestsProvider).valueOrNull != null &&
    ref.read(userSourcesStateProvider).valueOrNull != null;

/// Applique et persiste un réordre de la Tournée décrit par la séquence des
/// clés **effectivement rendues** ([visibleOrderedKeys], dans leur nouvel
/// ordre). No-op si les données d'appartenance ne sont pas prêtes.
///
/// Le réordre est non destructif : toute clé de l'ordre absente de
/// [visibleOrderedKeys] (tuile non matérialisée, clé masquée, ou onglet figé
/// comme `grille`) est préservée à sa position absolue.
Future<void> persistTourneeEssentielReorder(
  WidgetRef ref,
  List<String> visibleOrderedKeys,
) async {
  if (!tourneeMembershipDataReady(ref)) return;

  final notifier = ref.read(tourneeOrderPrefsProvider.notifier);
  await notifier.markCustomized();
  final prevOrder = ref.read(tourneeOrderPrefsProvider).order;
  await notifier.setOrder(mergeVisibleReorder(prevOrder, visibleOrderedKeys));

  final themeRefs = <FavoriteRef>[
    for (final key in visibleOrderedKeys)
      if (key.startsWith('theme:'))
        ThemeFavoriteRef(slug: key.substring('theme:'.length)),
  ];
  final sourceIds = [
    for (final key in visibleOrderedKeys)
      if (key.startsWith('source:')) key.substring('source:'.length),
  ];
  await Future.wait([
    syncTourneeThemePositions(ref, themeRefs),
    syncSourcePositionsMerged(ref, sourceIds, essentiel: true),
  ]);
}

/// Réordonne les `ThemeFavoriteRef` serveur en préservant veille/custom-topics.
Future<void> syncTourneeThemePositions(
  WidgetRef ref,
  List<FavoriteRef> themeRefs,
) async {
  final interests = ref.read(userInterestsProvider).valueOrNull;
  if (interests == null) return;
  final themeSlots = interests.favorites.whereType<ThemeFavoriteRef>().length;
  if (themeRefs.length != themeSlots) return;
  var i = 0;
  final merged = [
    for (final f in interests.favorites)
      f is ThemeFavoriteRef ? themeRefs[i++] : f,
  ];
  try {
    await ref.read(userInterestsProvider.notifier).reorderFavorites(merged);
  } catch (_) {
    // best-effort.
  }
}

/// Réassigne les positions serveur des sources favorites **sans jamais perdre**
/// celles de l'autre section : `reorderFavorites` remplace toute la liste, donc
/// on fusionne le sous-ensemble réordonné avec l'autre mode.
Future<void> syncSourcePositionsMerged(
  WidgetRef ref,
  List<String> reorderedIds, {
  required bool essentiel,
}) async {
  final sourcesState = ref.read(userSourcesStateProvider).valueOrNull;
  if (sourcesState == null) return;
  final tournee = ref.read(tourneeOrderPrefsProvider);
  bool isEssentiel(String id) => tournee.sourceIsEssentiel(id);
  final reorderedSet = reorderedIds.toSet();
  final others = [
    for (final f in [
      ...sourcesState.favorites,
    ]..sort((a, b) => a.position.compareTo(b.position)))
      if ((essentiel ? !isEssentiel(f.sourceId) : isEssentiel(f.sourceId)) &&
          !reorderedSet.contains(f.sourceId))
        f.sourceId,
  ];
  final fullIds = essentiel
      ? [...reorderedIds, ...others]
      : [...others, ...reorderedIds];
  final refs = [
    for (var i = 0; i < fullIds.length; i++)
      SourceFavoriteRef(sourceId: fullIds[i], position: i),
  ];
  try {
    await ref.read(userSourcesStateProvider.notifier).reorderFavorites(refs);
  } catch (_) {
    // best-effort : l'ordre prefs reste appliqué.
  }
}
