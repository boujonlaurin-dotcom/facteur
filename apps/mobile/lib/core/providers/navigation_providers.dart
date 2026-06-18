import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Déclencheur de scroll-to-top pour l'onglet Flâner.
///
/// Incrémenté par le shell (`MainShell`) quand l'utilisateur re-tape l'onglet
/// déjà actif ; `FlanerScreen` l'écoute via `ref.listen` et appelle son
/// `_scrollToTop()`.
final feedScrollTriggerProvider = StateProvider<int>((ref) => 0);

/// Déclencheur de scroll-to-top pour l'onglet L'Essentiel (Flux Continu).
///
/// Miroir de [feedScrollTriggerProvider] : incrémenté par `MainShell` au re-tap
/// de l'onglet actif, écouté par `FluxContinuScreen`.
final essentielScrollTriggerProvider = StateProvider<int>((ref) => 0);

/// Last dedicated Tournée section visited during the current app session.
///
/// Detail pages update it as they are opened/replaced. When the route chain
/// closes, FluxContinuScreen consumes the key and scrolls to the matching
/// existing section anchor.
final tourneeLastDedicatedSectionProvider = StateProvider<String?>(
  (ref) => null,
);

/// Cible de scroll demandée par le tour guidé : le bridge y pose la `GlobalKey`
/// de la section à révéler (`tourActusSectionKey`) pendant l'étape « descends
/// dans tes cartes ». `FluxContinuScreen` l'écoute et `ensureVisible` la cible,
/// puis remet le provider à `null`. `StateProvider` plutôt qu'un trigger compteur
/// car la valeur transporte la clé elle-même.
final tourScrollTargetProvider = StateProvider<GlobalKey?>((ref) => null);

/// Visibilité du footer (MainBottomNav) — masqué au scroll vers le bas, révélé
/// au scroll vers le haut, partout dans l'app (comportement LinkedIn).
///
/// Écrit par les écrans scrollables (`FluxContinuScreen`, `FlanerScreen`) dans
/// leur `_onScroll` ; lu par `MainTabPageScaffold` qui glisse la barre hors
/// écran (`AnimatedSlide` + `IgnorePointer`). Reconquiert ~50px + safe-area en
/// lecture et garantit que le bas de carte (« Lire plus ») n'est jamais couvert
/// par le footer. Toujours remis à `true` au changement d'onglet / retour haut
/// pour qu'il ne reste pas « collé » masqué.
final footerVisibleProvider = StateProvider<bool>((ref) => true);

/// Met à jour [footerVisibleProvider] uniquement sur un vrai changement (le
/// footer partagé le lit via `MainTabPageScaffold`). Appelé depuis les
/// `_onScroll` des écrans scrollables (`FluxContinuScreen`, `FlanerScreen`) :
/// le no-op quand inchangé évite d'écrire à chaque frame de scroll.
void updateFooterVisibility(WidgetRef ref, bool visible) {
  final notifier = ref.read(footerVisibleProvider.notifier);
  if (notifier.state != visible) notifier.state = visible;
}
