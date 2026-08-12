import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  // Rebuild a fresh notifier whenever the authenticated user changes — logout,
  // then a different account on the same device. The local Hive mirror is
  // namespaced per user (`serein_enabled:$userId`) so the boot state is
  // restored synchronously for the CURRENT account, and userB never inherits
  // userA's preference. The server sync (initFromApi) still reconciles
  // cross-device.
  final userId = ref.watch(authStateProvider.select((s) => s.user?.id));
  return SereinToggleNotifier(ref, userId);
});

class SereinToggleNotifier extends StateNotifier<SereinToggleState> {
  final Ref _ref;
  final String? _userId;

  /// True once the server preference has been reconciled once, OR the user has
  /// made an explicit choice (`toggle`). Decoupled from [isLoading] because the
  /// state is no longer loading at boot as soon as a local mirror exists — so
  /// we can't reuse `!isLoading` as the one-shot guard anymore.
  bool _serverReconciled = false;

  SereinToggleNotifier(this._ref, this._userId)
      : super(_initialState(_userId));

  static const String _boxName = 'settings';

  static String _key(String userId) => 'serein_enabled:$userId';

  /// Synchronous boot state, restored from the per-user Hive mirror written on
  /// [toggle] / [initFromApi]. No user or an
  /// unopened box (unit tests) → legacy `enabled:false, isLoading:true`.
  static SereinToggleState _initialState(String? userId) {
    if (userId == null || !Hive.isBoxOpen(_boxName)) {
      return const SereinToggleState();
    }
    final saved = Hive.box<dynamic>(_boxName).get(_key(userId)) as bool?;
    if (saved == null) return const SereinToggleState();
    return SereinToggleState(enabled: saved, isLoading: false);
  }

  void _persistLocal(bool value) {
    if (_userId == null || !Hive.isBoxOpen(_boxName)) return;
    Hive.box<dynamic>(_boxName).put(_key(_userId!), value);
  }

  /// Sync with the server preference returned by /digest/both.
  ///
  /// Reconciles only ONCE. Once the toggle has stabilised — reconciled with the
  /// server or explicitly toggled — a digest re-fetch (scroll, navigation to
  /// Actus du jour, stale-fallback refresh) must NEVER overwrite the current
  /// choice, otherwise serein silently flips back OFF mid-session.
  void initFromApi(bool sereinEnabled) {
    if (_serverReconciled) return;
    _serverReconciled = true;
    state = SereinToggleState(enabled: sereinEnabled, isLoading: false);
    _persistLocal(sereinEnabled);
  }

  /// Single-digest 404 fallback: it carries no serein flag, so just lift
  /// [isLoading] when nothing is known yet. It never persists the local mirror
  /// nor marks the reconciliation done — a real sync via [initFromApi] can
  /// still arrive and set the actual value.
  void markLoadedFromFallback() {
    if (_serverReconciled || !state.isLoading) return;
    state = state.copyWith(isLoading: false);
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

    // 2. An explicit choice freezes any later server reconciliation and is
    //    mirrored locally right away — so it survives a silently-failed PUT
    //    and the next cold start regardless of the network round-trip.
    _serverReconciled = true;
    _persistLocal(newValue);

    // 3. Haptic
    HapticFeedback.lightImpact();

    // 4. Persist preference server-side (fire-and-forget)
    try {
      final repository = _ref.read(digestRepositoryProvider);
      await repository.updatePreference(
        key: 'serein_enabled',
        value: newValue.toString(),
      );
    } catch (_) {
      // Silent fail — the local mirror already holds the choice; the server
      // preference is retried next session.
    }
  }
}
