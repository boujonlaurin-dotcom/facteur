/// Ordre des blocs de la Tournée par la **qualité de leur tête d'affiche** —
/// arithmétique pure, calquée sur `section_fit.dart` / `section_snap.dart` :
/// aucun binding Flutter, aucun accès réseau/prefs, donc testable sans le
/// bootstrap Hive/Supabase de la suite widget.
///
/// Motivation (plainte PO) : des blocs à 1 article remontaient en tête de
/// Tournée. La règle historique — dépriorisation **binaire** riches/maigres
/// (`thinKeys` + `demote` dans `_orderedTourneeKeys`) — ne classait pas, elle
/// se contentait de reléguer les blocs à ≤1 article sous les autres. On la
/// remplace par un vrai tri sur la **somme des 3 meilleurs scores** des
/// articles du bloc, score déjà renvoyé par le backend
/// (`Content.recommendationReason.scoreTotal`). Les slots manquants comptant 0,
/// un bloc à 1 article est structurellement pénalisé — ce qu'une moyenne
/// n'aurait pas fait.
///
/// Discipline d'application : l'ordre n'est **jamais** recalculé à chaque
/// recomposition (le fan-out en émet 10-15 : les blocs sauteraient sous les
/// yeux). Il est calculé une fois à la complétion du fan-out, gelé pour la
/// journée tournée (frontière 07h30 Paris) et rejoué tel quel ensuite —
/// cf. `FluxContinuNotifier._freezeScoreOrderIfNeeded`.
library;

import '../../feed/models/content_model.dart';
import '../../feed/providers/tab_order_prefs_provider.dart'
    show mergeVisibleReorder;

/// Somme des [topN] **meilleurs** scores de [items] (pas les [topN] premiers
/// affichés), chaque terme clampé à 0 et les slots manquants comptant 0.
///
/// Le clamp est nécessaire : `scoreTotal` peut être négatif (les pénalités du
/// scoring backend sont absolues, pas relatives) et un article puni ne doit pas
/// *retrancher* du crédit aux deux autres. Les articles sans
/// `recommendationReason` (blocs éditoriaux, veille sans scoring) ne
/// contribuent pas — c'est à l'appelant de décider si un bloc entièrement non
/// scoré entre dans le classement (cf. [rankKeysByBlockScore]).
double blockScore(List<Content> items, {int topN = 3}) {
  final scores = <double>[
    for (final item in items)
      if (item.recommendationReason != null)
        item.recommendationReason!.scoreTotal.clamp(0.0, double.infinity),
  ]..sort((a, b) => b.compareTo(a));
  var total = 0.0;
  for (var i = 0; i < topN && i < scores.length; i++) {
    total += scores[i];
  }
  return total;
}

/// Clés de [blockScores] triées par score **décroissant**.
///
/// Le tri est rendu stable à la main (`List.sort` ne l'est pas) : à score égal,
/// l'ordre d'itération de la map départage. Comme [blockScores] est construite
/// en parcourant les sections dans l'ordre d'affichage, c'est l'ordre
/// manuel/par défaut qui tranche les ex æquo.
///
/// Une section sans aucun article scoré n'entre jamais dans la map : elle est
/// donc absente du classement, et [applyScoreOrder] lui laisse son rang plutôt
/// que de la faire couler à 0.
List<String> rankKeysByBlockScore(Map<String, double> blockScores) {
  final keys = blockScores.keys.toList();
  final scored = <({String key, int i})>[
    for (var i = 0; i < keys.length; i++) (key: keys[i], i: i),
  ];
  scored.sort((a, b) {
    final cmp = blockScores[b.key]!.compareTo(blockScores[a.key]!);
    return cmp != 0 ? cmp : a.i.compareTo(b.i);
  });
  return [for (final e in scored) e.key];
}

/// Applique [scoreOrder] (l'ordre gelé de la journée) à [keys] : les clés
/// communes aux deux listes sont replacées dans l'ordre de [scoreOrder], les
/// autres restent à leur **position absolue**.
///
/// Réutilise [mergeVisibleReorder] — exactement la même sémantique que le
/// réordre partiel des favoris (les clés inconnues tiennent leur place plutôt
/// que d'être poussées en queue comme le ferait `applyOrder`, ce qui ferait
/// couler les blocs éditoriaux Actus/Bonnes). Une clé de [scoreOrder] absente
/// de [keys] (section disparue depuis le gel) est ignorée : la rajouter
/// consommerait un slot du cap pour une section inexistante.
List<String> applyScoreOrder(List<String> keys, List<String> scoreOrder) {
  final keySet = keys.toSet();
  return mergeVisibleReorder(keys, [
    for (final k in scoreOrder)
      if (keySet.contains(k)) k,
  ]);
}
