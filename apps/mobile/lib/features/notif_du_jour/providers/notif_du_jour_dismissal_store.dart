import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'notif_du_jour_day_store.dart';

/// Clé de persistance des dismiss durables. Suffixe `_v1` cohérent avec les
/// autres prefs (`notif_du_jour_state_v1`).
const String kNotifDuJourDismissalsKey = 'notif_du_jour_dismissals_v1';

/// Durée du cooldown après un dismiss (croix) : un message dismissé ne
/// réapparaît pas avant 30 jours. Complète le day store (cap 3/jour) : le day
/// store empêche le harcèlement *intra-journée*, le cooldown empêche le nag
/// *inter-jours* d'un message explicitement rejeté.
const int kNotifDismissCooldownDays = 30;

/// État persisté : map `{ id: 'YYYY-MM-DD' }` du dernier dismiss par message.
///
/// `loaded` gate anti-flash : la carte ne rend rien tant que les prefs ne sont
/// pas chargées (comme le day store), pour ne pas flasher un message en
/// cooldown le temps de lire le disque.
class NotifDuJourDismissalState {
  final bool loaded;
  final Map<String, String> dismissedOn;

  const NotifDuJourDismissalState({
    this.loaded = false,
    this.dismissedOn = const {},
  });

  /// Ids dismissés il y a moins de [kNotifDismissCooldownDays] jours (à
  /// filtrer de la file). [now] = jour vécu par l'utilisateur (même clé que le
  /// day store).
  Set<String> activeCooldownIds(DateTime now) {
    final active = <String>{};
    dismissedOn.forEach((id, day) {
      final at = DateTime.tryParse(day);
      if (at == null) return;
      if (now.difference(at).inDays < kNotifDismissCooldownDays) active.add(id);
    });
    return active;
  }
}

final notifDuJourDismissalStoreProvider =
    StateNotifierProvider<NotifDuJourDismissalStore, NotifDuJourDismissalState>(
      (ref) => NotifDuJourDismissalStore(),
    );

/// Store SharedPreferences des dismiss durables de la file « Notif du jour ».
///
/// Écritures best-effort (l'état mémoire reste appliqué pour la session si les
/// prefs échouent), clock injectable pour les tests — même pattern que le day
/// store.
class NotifDuJourDismissalStore
    extends StateNotifier<NotifDuJourDismissalState> {
  NotifDuJourDismissalStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const NotifDuJourDismissalState()) {
    _load();
  }

  final DateTime Function() _clock;

  Future<void> _load() async {
    var dismissedOn = const <String, String>{};
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kNotifDuJourDismissalsKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          dismissedOn = {
            for (final entry in decoded.entries)
              if (entry.value is String) entry.key: entry.value as String,
          };
        }
      }
    } catch (_) {
      // best-effort : prefs illisibles → repart sans cooldown.
    }
    if (!mounted) return;
    state = NotifDuJourDismissalState(loaded: true, dismissedOn: dismissedOn);
  }

  /// Pose le cooldown sur [id] (dismiss croix) et persiste.
  Future<void> recordDismissed(String id) async {
    final today = notifDuJourDayKey(_clock());
    final dismissedOn = {...state.dismissedOn, id: today};
    state = NotifDuJourDismissalState(loaded: true, dismissedOn: dismissedOn);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(kNotifDuJourDismissalsKey, jsonEncode(dismissedOn));
    } catch (_) {
      // best-effort.
    }
  }
}
