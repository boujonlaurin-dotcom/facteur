import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import 'digest_provider.dart';

/// Global serein toggle state — shared between Digest and Feed.
class SereinToggleState {
  final bool enabled;
  final bool isLoading;

  const SereinToggleState({
    this.enabled = false,
    this.isLoading = true,
  });

  SereinToggleState copyWith({bool? enabled, bool? isLoading}) {
    return SereinToggleState(
      enabled: enabled ?? this.enabled,
      isLoading: isLoading ?? this.isLoading,
    );
  }
}

final sereinToggleProvider =
    StateNotifierProvider<SereinToggleNotifier, SereinToggleState>((ref) {
  // Rebuild a fresh notifier (back to isLoading:true) whenever the
  // authenticated user changes — logout, then a different account on the same
  // device. Otherwise the initFromApi guard below would block the next user's
  // server preference from ever applying and they'd inherit the previous
  // user's toggle.
  ref.watch(authStateProvider.select((s) => s.user?.id));
  return SereinToggleNotifier(ref);
});

class SereinToggleNotifier extends StateNotifier<SereinToggleState> {
  final Ref _ref;

  SereinToggleNotifier(this._ref) : super(const SereinToggleState());

  /// Sync with the server preference returned by /digest/both.
  ///
  /// Only syncs on the FIRST load (while still [isLoading]). Once the toggle
  /// has stabilised, a digest re-fetch (scroll, navigation to Actus du jour,
  /// stale-fallback refresh) must NEVER overwrite the user's current choice —
  /// otherwise serein silently flips back OFF mid-session.
  void initFromApi(bool sereinEnabled) {
    if (!state.isLoading) return;
    state = SereinToggleState(enabled: sereinEnabled, isLoading: false);
  }

  /// Change the local view mode without persisting the preference.
  /// Used when the user opens "Lecture apaisée" from the feed entry card —
  /// we want serein content for this visit only, not flip their saved
  /// preference.
  void setEnabledLocal(bool enabled) {
    state = state.copyWith(enabled: enabled);
  }

  /// Instant toggle — UI flips immediately, preference saved in background.
  Future<void> toggle() async {
    final newValue = !state.enabled;

    // 1. Immediate UI update
    state = state.copyWith(enabled: newValue);

    // 2. Haptic
    HapticFeedback.lightImpact();

    // 3. Persist preference (fire-and-forget)
    try {
      final repository = _ref.read(digestRepositoryProvider);
      await repository.updatePreference(
        key: 'serein_enabled',
        value: newValue.toString(),
      );
    } catch (_) {
      // Silent fail — preference retried next session
    }
  }
}
