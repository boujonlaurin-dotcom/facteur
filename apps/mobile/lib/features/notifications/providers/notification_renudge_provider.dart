import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../settings/providers/notifications_settings_provider.dart';

/// Cap : maximum 3 affichages du re-nudge au total (brief §5.1).
const int kRenudgeMaxShown = 3;

/// Délai minimum après le refus initial avant le 1er re-nudge (≥7j).
const Duration kRenudgeMinSinceRefusal = Duration(days: 7);

/// Espacement minimum entre deux re-nudges (≤1× toutes les 2 semaines).
const Duration kRenudgeMinBetween = Duration(days: 14);

bool shouldShowRenudge(NotificationsSettings s, {required DateTime now}) {
  if (s.pushEnabled) return false;
  if (s.renudgeShownCount >= kRenudgeMaxShown) return false;

  final lastRefusal = s.lastRefusalAt;
  if (lastRefusal == null) return false;
  if (now.difference(lastRefusal) < kRenudgeMinSinceRefusal) return false;

  final lastRenudge = s.lastRenudgeAt;
  if (lastRenudge != null && now.difference(lastRenudge) < kRenudgeMinBetween) {
    return false;
  }

  return true;
}

/// Provider qui calcule à la volée si le re-nudge doit s'afficher.
final notificationRenudgeShouldShowProvider = Provider<bool>((ref) {
  final settings = ref.watch(notificationsSettingsProvider);
  return shouldShowRenudge(settings, now: DateTime.now().toUtc());
});
