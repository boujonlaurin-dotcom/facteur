## Tour guidé Facteur (coach-mark post-onboarding)

Tour guidé en 5 étapes joué **une seule fois juste après l'onboarding**, qui pilote la vraie app pour présenter ses pages principales. Il s'insère **avant** les modales post-onboarding existantes (thème puis notifications).

### Parcours (6 états joués, 5 puces)
1. **1/5** — hero « L'Essentiel du jour » + onglet Essentiel (scroll top).
2. **2/5 (a)** — scroll vers la 1ʳᵉ section de la Tournée (`ensureVisible`).
3. **2/5 (b)** — ouverture de la vraie feuille « Mes favoris », spotlight par-dessus.
4. **3/5** — bascule onglet Flâner, voile plein, carte centrée.
5. **4/5** — retour accueil, spotlight de l'avatar profil (Réglages).
6. **5/5** — même avatar (Mon courrier), bouton « Terminer ».
7. **done** — carte « C'est parti », puis main rendue aux modales.

### Architecture
- **Machine à états Riverpod** (`GuidedTourController`, `keepAlive`) — survit aux changements d'onglet/feuilles, **ne touche jamais `BuildContext`**. `start(onComplete)` gate le flag « vu » (scopé user) ; `next()`/`skip()`/`finish()` → `done` + `onComplete` tiré une seule fois.
- **Bridge racine** (`GuidedTourBridge`, monté une fois dans `MainShell`) — exécute les effets de bord (navigation, ouverture feuille, scroll) et insère l'`OverlayEntry` dans l'overlay **racine** (au-dessus de la feuille favoris qui vit en branche).
- **Overlay** — scrim `#2C2A29` α0.72 + découpe spotlight (`Path`/`BlendMode.clear`, contour `#E8943F`), rect relu live depuis le `RenderBox` des `GlobalKey` à chaque frame (suit slide/scroll). Coach card : avatar Facteur, pastille « N/5 », titre Fraunces, corps DM Sans, 5 puces, Passer/Suivant/Terminer.

### Garde « une seule fois »
Double verrou : démarrage seulement depuis le chemin post-onboarding (`postOnboardingFlowPendingProvider`) **et** flag persistant `nudge.guided_tour.seen.<userId>` (namespace `nudge.`, scopé user comme `NudgeStorage`).

### Fichiers
- **Nouveaux** : `lib/features/tour/` (models/tour_step, providers/guided_tour_controller, tour_anchors, tour_strings, tour_ids, widgets/guided_tour_bridge|overlay|coach_card).
- **Édités** : `flux_continu_screen.dart` (split `_runPostOnboardingFlow` → tour puis `_runPostOnboardingModals`, listen `tourScrollTargetProvider`, ancre 1ʳᵉ section), `essentiel_hi_fi_card.dart` (ancre hero), `main_shell.dart` (montage bridge + ancre avatar), `main_bottom_nav.dart` (ancre onglet), `manage_favorites_sheet.dart` (ancre feuille + note z-order), `navigation_providers.dart` (`tourScrollTargetProvider`), `changelog.json`.

### Tests
- `test/features/tour/guided_tour_controller_test.dart` — séquence complète, displayIndex (2/5 mutualisé), skip/finish → done + flag persisté + onComplete une fois, no-op si déjà vu.
- `test/features/tour/guided_tour_overlay_test.dart` — coach card (titre/pastille/puces/boutons), « Terminer » en dernière étape, carte de conclusion, voile plein sans ancre.
- `flutter analyze` : 0 nouvelle erreur. Tests des fichiers touchés (essentiel_hi_fi_card, main_bottom_nav, flux_continu) : verts.

### Notes
- Frontend pur, aucune migration / endpoint.
- Reste à faire avant deploy : `/validate-feature` Playwright (handoff dans `.context/qa-handoff.md`).
