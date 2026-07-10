import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Clé de persistance de l'état du jour. Suffixe `_v1` cohérent avec les
/// autres prefs (`lettres_banner_last_shown_v1`).
const String kNotifDuJourStateKey = 'notif_du_jour_state_v1';

/// Plafond de messages consommés (tap ou dismiss) par jour.
const int kNotifDuJourDailyCap = 3;

/// Clé jour locale `YYYY-MM-DD` (le rythme « du jour » suit la journée vécue
/// par l'utilisateur, pas UTC).
String notifDuJourDayKey(DateTime now) =>
    now.toIso8601String().substring(0, 10);

/// État persisté : jour courant + ids consommés aujourd'hui.
///
/// `loaded` gate anti-flash : la carte ne rend rien tant que les prefs ne
/// sont pas chargées (pattern du throttle du bandeau Lettres).
class NotifDuJourDayState {
  final bool loaded;
  final String day;
  final List<String> consumed;

  const NotifDuJourDayState({
    this.loaded = false,
    this.day = '',
    this.consumed = const [],
  });

  bool get capReached => consumed.length >= kNotifDuJourDailyCap;
}

final notifDuJourDayStoreProvider =
    StateNotifierProvider<NotifDuJourDayStore, NotifDuJourDayState>((ref) {
      return NotifDuJourDayStore();
    });

/// Store SharedPreferences day-scoped de la file « Notif du jour ».
///
/// Au chargement : si le jour persisté n'est plus aujourd'hui → reset des
/// consommés. Écritures best-effort (l'état mémoire reste appliqué pour la
/// session si les prefs échouent).
class NotifDuJourDayStore extends StateNotifier<NotifDuJourDayState> {
  NotifDuJourDayStore({DateTime Function()? clock})
    : _clock = clock ?? DateTime.now,
      super(const NotifDuJourDayState()) {
    _load();
  }

  final DateTime Function() _clock;

  Future<void> _load() async {
    final today = notifDuJourDayKey(_clock());
    var consumed = const <String>[];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(kNotifDuJourStateKey);
      if (raw != null) {
        final decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic> && decoded['day'] == today) {
          consumed = [
            for (final id in (decoded['consumed'] as List? ?? const []))
              if (id is String) id,
          ];
        }
      }
    } catch (_) {
      // best-effort : prefs illisibles → repart d'un jour vierge.
    }
    if (!mounted) return;
    state = NotifDuJourDayState(loaded: true, day: today, consumed: consumed);
  }

  /// Consomme [id] pour la journée (tap CTA *ou* dismiss) et persiste.
  /// Le prochain build de la carte fait apparaître le message suivant.
  Future<void> consume(String id) async {
    final today = notifDuJourDayKey(_clock());
    final consumed = state.day == today
        ? [...state.consumed]
        : <String>[]; // minuit franchi depuis le chargement → reset
    if (!consumed.contains(id)) consumed.add(id);
    state = NotifDuJourDayState(loaded: true, day: today, consumed: consumed);
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        kNotifDuJourStateKey,
        jsonEncode({'day': today, 'consumed': consumed}),
      );
    } catch (_) {
      // best-effort.
    }
  }
}
