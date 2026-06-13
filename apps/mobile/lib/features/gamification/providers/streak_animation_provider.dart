import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'gamification_preference_provider.dart';

typedef StreakAnimationClock = DateTime Function();

final streakAnimationClockProvider = Provider<StreakAnimationClock>((ref) {
  return DateTime.now;
});

class StreakDailyAnimationGate {
  StreakDailyAnimationGate({
    required StreakAnimationClock now,
    Future<SharedPreferences> Function()? prefsFactory,
  }) : _now = now,
       _prefsFactory = prefsFactory ?? SharedPreferences.getInstance;

  static const _prefsKey = 'streak_indicator_last_animation_date';
  final StreakAnimationClock _now;
  final Future<SharedPreferences> Function() _prefsFactory;

  Future<bool> shouldAnimateToday() async {
    final prefs = await _prefsFactory();
    return prefs.getString(_prefsKey) != _todayKey();
  }

  Future<void> markAnimatedForToday() async {
    final prefs = await _prefsFactory();
    await prefs.setString(_prefsKey, _todayKey());
  }

  String _todayKey() => _now().toIso8601String().split('T').first;
}

final streakDailyAnimationGateProvider = Provider<StreakDailyAnimationGate>((
  ref,
) {
  return StreakDailyAnimationGate(now: ref.watch(streakAnimationClockProvider));
});

final streakDailyAnimationProvider = FutureProvider<bool>((ref) async {
  final enabled = await ref.watch(gamificationPreferenceProvider.future);
  if (!enabled) return false;

  final gate = ref.watch(streakDailyAnimationGateProvider);
  return gate.shouldAnimateToday();
});
