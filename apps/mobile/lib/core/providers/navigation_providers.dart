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
