import 'package:flutter/widgets.dart';

/// GlobalKeys partagées du tour guidé, posées sur les éléments réels de l'app
/// que le spotlight vient cerner (pattern `feed_nudge_anchors.dart` : clés
/// module-level, jamais dupliquées).
///
/// Le bridge ([GuidedTourBridge]) lit le `RenderBox` de chaque clé à chaque
/// frame pour suivre l'élément pendant les slides d'onglet et les scrolls.

/// Hero « L'Essentiel du jour » (carte hi-fi) — étape 1.
final GlobalKey tourEssentielHeroKey = GlobalKey(
  debugLabel: 'tourEssentielHeroKey',
);

/// Onglet « L'Essentiel » du footer — co-cible de l'étape 1.
final GlobalKey tourEssentielFooterTabKey = GlobalKey(
  debugLabel: 'tourEssentielFooterTabKey',
);

/// Première section de contenu de la Tournée (après le hero) — étape 2a.
final GlobalKey tourActusSectionKey = GlobalKey(
  debugLabel: 'tourActusSectionKey',
);

/// Avatar profil (haut-droite du header partagé) — étapes 4 & 5.
final GlobalKey tourProfileAvatarKey = GlobalKey(
  debugLabel: 'tourProfileAvatarKey',
);

/// Racine de la feuille « Mes favoris » ouverte — étape 2b. Le spotlight la
/// cerne par-dessus : l'overlay est inséré dans l'overlay **racine** alors que
/// la feuille vit dans le navigator de branche (cf. `manage_favorites_sheet.dart`).
final GlobalKey tourFavorisSheetKey = GlobalKey(
  debugLabel: 'tourFavorisSheetKey',
);
