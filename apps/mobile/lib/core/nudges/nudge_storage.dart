import 'package:shared_preferences/shared_preferences.dart';

import 'nudge.dart';

/// Persistence layer for nudges.
///
/// Keys are namespaced as `nudge.<id>.seen` / `nudge.<id>.lastShown`.
///
/// When a [Nudge] declares a [Nudge.legacySeenKey] or [Nudge.legacyLastShownKey],
/// reads fall back to the legacy key so users upgrading from an older build
/// keep their "seen" state. Writes always target the new namespaced key;
/// the legacy key is also updated for defensive rollback.
class NudgeStorage {
  static const _seenPrefix = 'nudge.';
  static const _seenSuffix = '.seen';
  static const _lastShownSuffix = '.lastShown';

  NudgeStorage({SharedPreferences? prefs}) : _prefsOverride = prefs;

  final SharedPreferences? _prefsOverride;

  Future<SharedPreferences> _prefs() async =>
      _prefsOverride ?? await SharedPreferences.getInstance();

  String _seenKey(String id) => '$_seenPrefix$id$_seenSuffix';
  String _lastShownKey(String id) => '$_seenPrefix$id$_lastShownSuffix';
  String _userSeenKey(String id, String userId) =>
      '$_seenPrefix$id$_seenSuffix.$userId';

  Future<bool> isSeen(Nudge nudge) async {
    final prefs = await _prefs();
    final namespaced = prefs.getBool(_seenKey(nudge.id));
    if (namespaced != null) return namespaced;
    final legacy = nudge.legacySeenKey;
    if (legacy != null) {
      return prefs.getBool(legacy) ?? false;
    }
    return false;
  }

  Future<void> markSeen(Nudge nudge) async {
    final prefs = await _prefs();
    await prefs.setBool(_seenKey(nudge.id), true);
    final legacy = nudge.legacySeenKey;
    if (legacy != null) {
      await prefs.setBool(legacy, true);
    }
  }

  /// User-scoped variant for nudges whose "seen" semantics are per-user, not
  /// per-device (e.g., the welcome tour that introduces the app — a second
  /// account on the same device must see it independently).
  ///
  /// Does NOT honor the device-scoped legacy key as a block: we can't know
  /// which user marked it seen, and blocking new users would reproduce the
  /// bug this API exists to fix. The user who saw the tour in v1 may see it
  /// once more on their next boot; after [markSeenForUser] they won't again.
  Future<bool> isSeenForUser(Nudge nudge, String userId) async {
    final prefs = await _prefs();
    final userScoped = prefs.getBool(_userSeenKey(nudge.id, userId));
    return userScoped ?? false;
  }

  Future<void> markSeenForUser(Nudge nudge, String userId) async {
    final prefs = await _prefs();
    await prefs.setBool(_userSeenKey(nudge.id, userId), true);
    await prefs.setBool(_seenKey(nudge.id), true);
  }

  Future<DateTime?> lastShown(Nudge nudge) async {
    final prefs = await _prefs();
    final namespacedMs = prefs.getInt(_lastShownKey(nudge.id));
    if (namespacedMs != null) {
      return DateTime.fromMillisecondsSinceEpoch(namespacedMs);
    }
    final legacy = nudge.legacyLastShownKey;
    if (legacy != null) {
      final raw = prefs.get(legacy);
      if (raw is int) {
        return DateTime.fromMillisecondsSinceEpoch(raw);
      }
      if (raw is String) {
        return DateTime.tryParse(raw);
      }
    }
    return null;
  }

  Future<void> recordShown(Nudge nudge, {DateTime? at}) async {
    final prefs = await _prefs();
    final when = at ?? DateTime.now();
    await prefs.setInt(_lastShownKey(nudge.id), when.millisecondsSinceEpoch);
    final legacy = nudge.legacyLastShownKey;
    if (legacy != null) {
      await prefs.setInt(legacy, when.millisecondsSinceEpoch);
    }
  }

  /// Test helper: clear every namespaced key (does not touch legacy keys).
  Future<void> clearAll() async {
    final prefs = await _prefs();
    final keys = prefs.getKeys().where((k) => k.startsWith(_seenPrefix));
    for (final k in keys) {
      await prefs.remove(k);
    }
  }
}
