import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_state.dart';
import '../web/web_perf.dart';
import '../../features/notifications/providers/notification_renudge_provider.dart';
import '../../features/flux_continu/providers/geoloc_prompt_provider.dart';
import '../../features/onboarding/providers/ios_add_to_home_provider.dart';
import '../../features/settings/providers/notifications_settings_provider.dart';
import '../../features/well_informed/providers/well_informed_prompt_provider.dart';

/// Slot d'engagement éligible à l'arrivée sur le Feed.
///
/// Garantit qu'au plus **un** overlay modal ET **un** nudge inline sont
/// éligibles à un instant donné. Sans cet arbitrage, modal notif, re-nudge
/// banner et well-informed prompt se cumulaient.
enum FirstImpressionSlot {
  none,
  iosAddToHome,
  notifModal,
  renudgeBanner,
  wellInformed,
  geolocPrompt,
}

/// Une fois la modal notif affichée dans la session, on ne déclenche aucun
/// nudge (re-nudge, well-informed) avant le prochain cold start.
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

/// Une fois un nudge consommé, on n'en affiche pas un second avant cold start.
final nudgeConsumedThisSessionProvider = StateProvider<bool>((_) => false);

/// Décide quel slot d'engagement est éligible à un instant `t`.
///
/// Règles :
/// 1. Onboarding pas terminé → rien (l'onboarding occupe toute la fenêtre).
/// 2. iOS Safari non standalone ET pas déjà consommé → `iosAddToHome`
///    (priorité max sur web : c'est le seul levier d'install).
/// 3. Sync préfs notif terminé ET `modalSeen=false` ET pas déjà consommé →
///    `notifModal`.
/// 4. Re-nudge éligible (cap, espacement, refus passé) ET aucun nudge déjà
///    consommé cette session → `renudgeBanner`.
/// 5. Well-informed prompt dû ET aucun nudge déjà consommé → `wellInformed`.
/// 6. Géoloc due (≥5 ouvertures, pas device, cap) ET aucun nudge consommé →
///    `geolocPrompt` (priorité la plus basse).
final firstImpressionSlotProvider = Provider<FirstImpressionSlot>((ref) {
  final auth = ref.watch(authStateProvider);
  final notif = ref.watch(notificationsSettingsProvider);
  final modalConsumed = ref.watch(notifModalConsumedThisSessionProvider);
  final nudgeConsumed = ref.watch(nudgeConsumedThisSessionProvider);
  final renudgeShould = ref.watch(notificationRenudgeShouldShowProvider);
  final wellInformedShould =
      ref.watch(wellInformedShouldShowProvider).valueOrNull ?? false;
  final iosAddToHomeShould =
      ref.watch(iosAddToHomeShouldShowProvider).valueOrNull ?? false;
  final iosAddToHomeConsumed =
      ref.watch(iosAddToHomeConsumedThisSessionProvider);
  final geolocPromptShould =
      ref.watch(geolocPromptShouldShowProvider).valueOrNull ?? false;

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

  if (!nudgeConsumed && renudgeShould) {
    return FirstImpressionSlot.renudgeBanner;
  }

  if (!nudgeConsumed && wellInformedShould) {
    return FirstImpressionSlot.wellInformed;
  }

  if (!nudgeConsumed && geolocPromptShould) {
    return FirstImpressionSlot.geolocPrompt;
  }

  return FirstImpressionSlot.none;
});
