# Maintenance — Barre de navigation Android transparente

## Contexte

Sur Android, la barre de navigation système (« footer » : boutons retour/accueil/récents
ou la pilule gestuelle) s'affichait en **noir opaque**, créant une rupture visuelle avec
le fond de l'app. Objectif : la rendre **transparente** (rendu edge-to-edge, façon
LinkedIn), pour que le contenu / la barre de navigation de l'app apparaisse derrière.

## Diagnostic

Deux causes :

1. `apps/mobile/lib/main.dart` — l'`SystemUiOverlayStyle` global ne définissait jamais
   `systemNavigationBarColor`, laissant la valeur système par défaut (noir).
2. `apps/mobile/lib/config/theme.dart` — `AppBarTheme.systemOverlayStyle` utilisait
   `SystemUiOverlayStyle.light` / `.dark`, dont la `systemNavigationBarColor` est **noire**.
   Chaque écran muni d'une `AppBar` repeignait donc la barre en noir.

## Changements

- **`main.dart`** :
  - Activation du mode `SystemUiMode.edgeToEdge` (le contenu dessine derrière les barres système).
  - `systemNavigationBarColor: Colors.black.withValues(alpha: 0.15)` — voile noir léger
    (et non full transparent) pour garantir le contraste de la pilule gestuelle / des
    boutons système sur les fonds clairs, tout en restant discret sur fonds sombres.
  - `systemNavigationBarContrastEnforced: false` (désactive le scrim auto d'Android qui
    réintroduit un fond opaque).
  - `systemNavigationBarIconBrightness` ajouté pour la lisibilité des icônes système.
- **`theme.dart`** : remplacement de `SystemUiOverlayStyle.light/.dark` par un style custom,
  avec le même voile noir léger (`Colors.black.withValues(alpha: 0.15)`) et la luminosité
  d'icônes (status bar + nav bar) adaptée au thème (clair / sombre).

Aucun changement Android natif requis : `_BottomNavBar` (shell_scaffold.dart) enveloppe déjà
sa `SafeArea` dans un `Container` coloré (`backgroundPrimary`), dont le fond peint
naturellement derrière la barre système (désormais un voile noir léger, quasi transparent).

## Vérification

- `flutter analyze` (lib/main.dart, lib/config/theme.dart)
- Test visuel sur device/émulateur Android : barre de navigation transparente sur les
  écrans avec et sans `AppBar`, en thèmes clair et sombre, contenu non masqué (SafeArea).
