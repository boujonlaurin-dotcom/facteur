import 'package:shared_preferences/shared_preferences.dart';

/// Simple persistent counters for nudge triggers (e.g., "open 4 articles
/// before showing read-on-site banner"). Device-scoped, namespaced.
class NudgeCounters {
  NudgeCounters._();

  static const String _prefix = 'nudge.counter.';

  static const String articleOpenCount = 'article_open_count';
  static const String articleWithPerspectivesCount =
      'article_with_perspectives_count';
  static const String feedOpenCount = 'feed_open_count';
  static const String feedCardTapCount = 'feed_card_tap_count';

  /// Returns the counter value after increment.
  static Future<int> increment(String counter) async {
    final prefs = await SharedPreferences.getInstance();
    final key = '$_prefix$counter';
    final next = (prefs.getInt(key) ?? 0) + 1;
    await prefs.setInt(key, next);
    return next;
  }

  static Future<int> get(String counter) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt('$_prefix$counter') ?? 0;
  }
}
