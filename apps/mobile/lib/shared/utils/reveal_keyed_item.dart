import 'package:flutter/material.dart';

/// Nombre de sauts d'écran autorisés pour aller construire un élément encore
/// non monté. Borne un feed long sans jamais boucler indéfiniment.
const int kRevealDefaultMaxHops = 12;

/// Amène en haut de l'écran l'élément désigné par [target], dans une liste
/// **paresseuse** pilotée par [controller].
///
/// `Scrollable.ensureVisible` seul ne suffit pas ici : un `SliverList` ne
/// construit que la fenêtre visible plus son `cacheExtent`, donc la cible n'a
/// souvent **aucun contexte** — l'appel ne fait rien et la liste reste où elle
/// était. On descend donc par sauts d'écran jusqu'à ce que la cible existe,
/// puis on cale dessus.
///
/// [target] est relu à chaque tour (la clé n'est posée qu'au moment où
/// l'élément est construit). Sans animation par défaut : on ne rejoue pas le
/// trajet, on rend une position déjà acquise ailleurs.
Future<void> revealKeyedItem({
  required ScrollController controller,
  required GlobalKey? Function() target,
  int maxHops = kRevealDefaultMaxHops,
  double alignment = 0.02,
  Duration duration = Duration.zero,
}) async {
  if (!controller.hasClients) return;
  for (var hop = 0; hop <= maxHops; hop++) {
    final ctx = target()?.currentContext;
    if (ctx != null && ctx.mounted) {
      await Scrollable.ensureVisible(
        ctx,
        duration: duration,
        alignment: alignment,
      );
      return;
    }
    if (!controller.hasClients) return;
    final position = controller.position;
    // 80 % d'écran par saut : assez pour avancer vite, assez peu pour ne pas
    // enjamber la cible (une carte fait moins d'un écran).
    final next = position.pixels + position.viewportDimension * 0.8;
    if (next >= position.maxScrollExtent) {
      // Bout de ce qui est chargé : la cible viendra avec la page suivante,
      // qu'on n'attend pas. On s'arrête là plutôt que de tourner à vide.
      if (position.pixels >= position.maxScrollExtent) return;
      controller.jumpTo(position.maxScrollExtent);
    } else {
      controller.jumpTo(next);
    }
    // Laisse le sliver construire les éléments de la nouvelle fenêtre.
    await WidgetsBinding.instance.endOfFrame;
  }
}
