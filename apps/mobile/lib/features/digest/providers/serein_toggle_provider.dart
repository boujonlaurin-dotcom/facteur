import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  return SereinToggleNotifier(ref);
});

class SereinToggleNotifier extends StateNotifier<SereinToggleState> {
  final Ref _ref;

  SereinToggleNotifier(this._ref) : super(const SereinToggleState());

  /// Called once when /digest/both returns to sync with server preference.
  void initFromApi(bool sereinEnabled) {
    state = SereinToggleState(enabled: sereinEnabled, isLoading: false);
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
