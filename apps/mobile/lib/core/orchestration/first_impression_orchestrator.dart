import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../web/web_perf.dart';
import '../../features/onboarding/providers/ios_add_to_home_provider.dart';
import '../../features/settings/providers/notifications_settings_provider.dart';

/// Slot d'engagement éligible à l'arrivée sur le Feed.
///
/// Ne porte plus que les **modales/overlays** (iOS add-to-home, activation
/// notif). Les nudges inline historiques (re-nudge, well-informed, géoloc)
/// sont absorbés dans la file « Notif du jour »
/// (`features/notif_du_jour/`), qui ne s'affiche que si ce slot est `none`.
enum FirstImpressionSlot {
  none,
  iosAddToHome,
  notifModal,
}

/// Une fois la modal notif affichée dans la session, on ne déclenche aucun
/// nudge avant le prochain cold start.
final notifModalConsumedThisSessionProvider = StateProvider<bool>((_) => false);

/// Flow post-onboarding en attente d'être joué sur l'écran Essentiel chargé.
///
/// Positionné par l'écran de conclusion **juste avant** de basculer
/// `needsOnboarding=false` (et donc avant la redirection router → Essentiel).
/// Consommé une seule fois par `FluxContinuScreen` quand son état passe en
/// `data` : la page Essentiel chargée sert alors de fond aux modales (thème
/// puis notifications), au lieu d'un Essentiel encore en chargement masqué par
/// un voile gris. La valeur porte la liste `failedCustomTopics` à résumer
/// (liste vide = flow à jouer sans dialog de customs échoués ; `null` = aucun
/// flow en attente).
final postOnboardingFlowPendingProvider =
    StateProvider<List<String>?>((_) => null);

/// Décide quel slot d'engagement est éligible à un instant `t`.
///
/// Règles :
/// 1. Onboarding pas terminé → rien (l'onboarding occupe toute la fenêtre).
/// 2. iOS Safari non standalone ET pas déjà consommé → `iosAddToHome`
///    (priorité max sur web : c'est le seul levier d'install).
/// 3. Sync préfs notif terminé ET `modalSeen=false` ET pas déjà consommé →
///    `notifModal`.
final firstImpressionSlotProvider = Provider<FirstImpressionSlot>((ref) {
  final auth = ref.watch(authStateProvider);
  final notif = ref.watch(notificationsSettingsProvider);
  final modalConsumed = ref.watch(notifModalConsumedThisSessionProvider);
  final iosAddToHomeShould =
      ref.watch(iosAddToHomeShouldShowProvider).valueOrNull ?? false;
  final iosAddToHomeConsumed =
      ref.watch(iosAddToHomeConsumedThisSessionProvider);

  if (!auth.isAuthenticated || !auth.isEmailConfirmed) {
    return FirstImpressionSlot.none;
  }
  if (auth.needsOnboarding) return FirstImpressionSlot.none;

  if (!iosAddToHomeConsumed && iosAddToHomeShould) {
    return FirstImpressionSlot.iosAddToHome;
  }

  if (kSupportsPushNotifications &&
      !modalConsumed &&
      notif.synced &&
      !notif.modalSeen) {
    return FirstImpressionSlot.notifModal;
  }

  return FirstImpressionSlot.none;
});
