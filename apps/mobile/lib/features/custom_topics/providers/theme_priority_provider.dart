import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _kThemePriorityPrefix = 'theme_priority_';

/// Provides theme priority multipliers (persisted in SharedPreferences).
/// Default: 1.0 (2/3 blocks) for all themes.
final themePriorityProvider = FutureProvider<Map<String, double>>((ref) async {
  final prefs = await SharedPreferences.getInstance();
  final result = <String, double>{};
  for (final key in prefs.getKeys()) {
    if (key.startsWith(_kThemePriorityPrefix)) {
      final theme = key.substring(_kThemePriorityPrefix.length);
      result[theme] = prefs.getDouble(key) ?? 1.0;
    }
  }
  return result;
});

/// Persists a theme priority multiplier to SharedPreferences.
Future<void> setThemePriority(String themeLabel, double multiplier) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setDouble('$_kThemePriorityPrefix$themeLabel', multiplier);
}
