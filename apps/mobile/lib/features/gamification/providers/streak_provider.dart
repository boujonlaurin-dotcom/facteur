import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../models/streak_model.dart';
import '../repositories/streak_repository.dart';

final streakRepositoryProvider = Provider<StreakRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return StreakRepository(apiClient);
});

final streakProvider = AsyncNotifierProvider<StreakNotifier, StreakModel>(() {
  return StreakNotifier();
});

class StreakNotifier extends AsyncNotifier<StreakModel> {
  @override
  FutureOr<StreakModel> build() async {
    final authState = ref.watch(authStateProvider);
    if (!authState.isAuthenticated) {
      return StreakModel(
        currentStreak: 0,
        longestStreak: 0,
        weeklyCount: 0,
        weeklyGoal: 10,
        weeklyProgress: 0.0,
      );
    }
    return _fetchStreak();
  }

  Future<StreakModel> _fetchStreak() async {
    final repository = ref.read(streakRepositoryProvider);
    return await repository.getStreak();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final newStreak = await _fetchStreak();
      state = AsyncData(newStreak);
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }

  // Called after consumption
  Future<void> refreshSilent() async {
    try {
      final newStreak = await _fetchStreak();
      state = AsyncData(newStreak);
    } catch (e) {
      // Ignore errors on silent refresh
    }
  }
}
