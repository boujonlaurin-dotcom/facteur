import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Notifier to track consecutive "skips" of sources in the current session.
class SkipNotifier extends StateNotifier<Map<String, int>> {
  SkipNotifier() : super({});

  /// Increment skip count for a source.
  void recordSkip(String sourceId) {
    final current = state[sourceId] ?? 0;
    state = {
      ...state,
      sourceId: current + 1,
    };
  }

  /// Reset skip count for a source (e.g., when the user opens an article from it).
  void recordInteraction(String sourceId) {
    if (state.containsKey(sourceId)) {
      state = Map.from(state)..remove(sourceId);
    }
  }

  /// Reset a skip count after showing a nudge and it being acknowledged/dismissed.
  void clearSkip(String sourceId) {
    if (state.containsKey(sourceId)) {
      state = Map.from(state)..remove(sourceId);
    }
  }
}

final skipProvider =
    StateNotifierProvider<SkipNotifier, Map<String, int>>((ref) {
  return SkipNotifier();
});
