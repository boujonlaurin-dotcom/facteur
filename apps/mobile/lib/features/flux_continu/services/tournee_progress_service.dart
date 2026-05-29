import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

/// SharedPreferences instance injected by the app bootstrap.
///
/// Unit tests and providers that are allowed to await can omit the override:
/// [TourneeProgressService] will lazily call [SharedPreferences.getInstance].
final sharedPreferencesProvider = Provider<SharedPreferences?>((ref) => null);

final tourneeProgressServiceProvider = Provider<TourneeProgressService>((ref) {
  return TourneeProgressService(prefs: ref.watch(sharedPreferencesProvider));
});

const String kFoldedPrefsKeyPrefix = 'flux_continu_folded_';
const String kClosingPrefsKeyPrefix = 'flux_continu_closing_dismissed_';

/// Boundary hour (Paris time) at which the "tournée day" flips.
const int kTourneeDayBoundaryHour = 7;
const int kTourneeDayBoundaryMinute = 30;
const String kTourneeDayBoundaryTz = 'Europe/Paris';

tz.Location? _parisLocation;

tz.Location _parisTz() {
  if (_parisLocation != null) return _parisLocation!;
  tz_data.initializeTimeZones();
  return _parisLocation = tz.getLocation(kTourneeDayBoundaryTz);
}

class TourneeProgressService {
  final SharedPreferences? _prefsOverride;

  const TourneeProgressService({SharedPreferences? prefs})
    : _prefsOverride = prefs;

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  /// Returns the canonical ISO day (`YYYY-MM-DD`) for the tournée at [now],
  /// using a 07:30 Europe/Paris boundary instead of midnight.
  static String dayKey(DateTime now) {
    final paris = tz.TZDateTime.from(now, _parisTz());
    final shifted =
        (paris.hour < kTourneeDayBoundaryHour ||
            (paris.hour == kTourneeDayBoundaryHour &&
                paris.minute < kTourneeDayBoundaryMinute))
        ? paris.subtract(const Duration(days: 1))
        : paris;
    return shifted.toIso8601String().substring(0, 10);
  }

  static String foldedPrefsKey(DateTime day) =>
      '$kFoldedPrefsKeyPrefix${dayKey(day)}';

  static String closingPrefsKey(DateTime day) =>
      '$kClosingPrefsKeyPrefix${dayKey(day)}';

  bool isClosingDismissedTodaySync({DateTime? now}) {
    final prefs = _prefsOverride;
    if (prefs == null) return false;
    return prefs.getBool(closingPrefsKey(now ?? DateTime.now())) ?? false;
  }

  Future<bool> loadClosingDismissedForToday({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      return prefs.getBool(closingPrefsKey(now ?? DateTime.now())) ?? false;
    } catch (e) {
      debugPrint('TourneeProgress: loadClosingDismissedForToday failed: $e');
      return false;
    }
  }

  Future<void> setClosingDismissedToday(bool dismissed, {DateTime? now}) async {
    try {
      final prefs = await _prefs();
      await prefs.setBool(closingPrefsKey(now ?? DateTime.now()), dismissed);
    } catch (e) {
      debugPrint('TourneeProgress: setClosingDismissedToday failed: $e');
    }
  }

  Future<Map<String, bool>> loadFoldedForToday({
    DateTime? now,
    bool Function(String key)? isLiveKey,
  }) async {
    try {
      final prefs = await _prefs();
      final names =
          prefs.getStringList(foldedPrefsKey(now ?? DateTime.now())) ??
          const <String>[];
      if (names.isEmpty) return const {};
      return {
        for (final name in names)
          if (isLiveKey == null || isLiveKey(name)) name: true,
      };
    } catch (e) {
      debugPrint('TourneeProgress: loadFoldedForToday failed: $e');
      return const {};
    }
  }

  Future<void> persistFolded(Map<String, bool> folded, {DateTime? now}) async {
    try {
      final prefs = await _prefs();
      final names = folded.entries
          .where((e) => e.value)
          .map((e) => e.key)
          .toList();
      await prefs.setStringList(foldedPrefsKey(now ?? DateTime.now()), names);
    } catch (e) {
      debugPrint('TourneeProgress: persistFolded failed: $e');
    }
  }

  Future<void> purgeOldPrefsKeys({DateTime? now}) async {
    try {
      final prefs = await _prefs();
      final today = now ?? DateTime.now();
      final foldedToday = foldedPrefsKey(today);
      final closingToday = closingPrefsKey(today);
      final stale = prefs.getKeys().where((k) {
        if (k.startsWith(kFoldedPrefsKeyPrefix) && k != foldedToday) {
          return true;
        }
        if (k.startsWith(kClosingPrefsKeyPrefix) && k != closingToday) {
          return true;
        }
        return false;
      }).toList();
      await Future.wait(stale.map(prefs.remove));
    } catch (e) {
      debugPrint('TourneeProgress: purgeOldPrefsKeys failed: $e');
    }
  }
}
