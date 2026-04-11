import 'package:shared_preferences/shared_preferences.dart';

/// Manages the 🌻 "Recommander ?" nudge display logic.
///
/// Simple session-scoped singleton — no Riverpod provider needed since
/// the state is only read/written from ContentDetailScreen.
///
/// Rules:
/// - Show after >30s of reading an article
/// - Skip the first 2 articles read in the session
/// - Max 1 nudge per session
/// - Max 1 nudge every 3 days (persisted via SharedPreferences)
/// - Don't show if article is already sunflowered
class NudgeTracker {
  static const _lastNudgeDateKey = 'sunflower_last_nudge_date';
  static const _nudgeCooldownDays = 3;

  // Session-scoped counters (reset on app restart)
  static int _articlesOpenedInSession = 0;
  static bool _nudgeShownThisSession = false;

  /// Call when a user opens an article
  static void recordArticleOpen() {
    _articlesOpenedInSession++;
  }

  /// Check if the nudge should be shown for the current article.
  static Future<bool> shouldShowNudge({
    required bool isAlreadySunflowered,
  }) async {
    if (isAlreadySunflowered) return false;
    if (_nudgeShownThisSession) return false;
    if (_articlesOpenedInSession <= 2) return false;

    try {
      final prefs = await SharedPreferences.getInstance();
      final lastNudgeDateStr = prefs.getString(_lastNudgeDateKey);
      if (lastNudgeDateStr != null) {
        final lastDate = DateTime.tryParse(lastNudgeDateStr);
        if (lastDate != null) {
          final daysSince = DateTime.now().difference(lastDate).inDays;
          if (daysSince < _nudgeCooldownDays) return false;
        }
      }
    } catch (_) {
      return false;
    }

    return true;
  }

  /// Mark nudge as shown (persists date for cooldown)
  static Future<void> markNudgeShown() async {
    _nudgeShownThisSession = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _lastNudgeDateKey,
        DateTime.now().toIso8601String(),
      );
    } catch (_) {
      // Best-effort persistence
    }
  }
}
