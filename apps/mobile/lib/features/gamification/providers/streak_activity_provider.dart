import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/streak_activity_model.dart';
import 'gamification_preference_provider.dart';
import 'streak_provider.dart';

final streakActivityProvider = FutureProvider.autoDispose<StreakActivityModel>((
  ref,
) async {
  final enabled = await ref.watch(gamificationPreferenceProvider.future);
  if (!enabled) return const StreakActivityModel.empty();

  final repository = ref.watch(streakRepositoryProvider);
  return repository.getActivity(days: 14);
});
