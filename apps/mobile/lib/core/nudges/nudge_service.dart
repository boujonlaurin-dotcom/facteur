import 'nudge.dart';
import 'nudge_registry.dart';
import 'nudge_storage.dart';

/// Lightweight, imperative facade over [NudgeStorage].
///
/// Use this for one-shot checks ("has the user seen X?"). For active-nudge
/// coordination (queue, priority, session budget) use [NudgeCoordinator].
class NudgeService {
  NudgeService({NudgeStorage? storage, DateTime Function()? clock})
      : _storage = storage ?? NudgeStorage(),
        _clock = clock ?? DateTime.now;

  final NudgeStorage _storage;
  final DateTime Function() _clock;

  /// Whether the given nudge may be shown right now, accounting for its
  /// frequency rule and seen/cooldown state.
  ///
  /// Prerequisites and the per-session budget are NOT checked here; those
  /// are enforced by [NudgeCoordinator]. Use this helper for simple
  /// once-only widgets that don't need queue coordination.
  Future<bool> canShow(String id) async {
    final nudge = NudgeRegistry.get(id);
    switch (nudge.frequency) {
      case NudgeFrequency.once:
        final seen = await _storage.isSeen(nudge);
        return !seen;
      case NudgeFrequency.session:
        // Session-scope is enforced by the coordinator; the service alone
        // cannot know about session state.
        return true;
      case NudgeFrequency.cooldown:
        final last = await _storage.lastShown(nudge);
        if (last == null) return true;
        return _clock().difference(last) >= nudge.cooldown!;
    }
  }

  Future<bool> isSeen(String id) async {
    final nudge = NudgeRegistry.get(id);
    return _storage.isSeen(nudge);
  }

  Future<void> markSeen(String id) async {
    final nudge = NudgeRegistry.get(id);
    await _storage.markSeen(nudge);
    await _storage.recordShown(nudge, at: _clock());
  }

  /// User-scoped variant: use for nudges whose "seen" semantics are per-user
  /// (welcome tour, account-specific intros), not per-device.
  Future<bool> isSeenForUser(String id, String userId) async {
    final nudge = NudgeRegistry.get(id);
    return _storage.isSeenForUser(nudge, userId);
  }

  Future<void> markSeenForUser(String id, String userId) async {
    final nudge = NudgeRegistry.get(id);
    await _storage.markSeenForUser(nudge, userId);
    await _storage.recordShown(nudge, at: _clock());
  }

  Future<void> markShown(String id, {DateTime? at}) async {
    final nudge = NudgeRegistry.get(id);
    await _storage.recordShown(nudge, at: at ?? _clock());
  }

  Future<DateTime?> lastShown(String id) async {
    final nudge = NudgeRegistry.get(id);
    return _storage.lastShown(nudge);
  }

  /// Convenience for once-frequency nudges: returns true the first time
  /// it's called per user, and marks the nudge as seen atomically.
  ///
  /// Preserves the semantics of the legacy `shouldShow()` helpers that
  /// existed on individual nudge widgets before unification.
  Future<bool> consumeFirstShow(String id) async {
    if (await isSeen(id)) return false;
    await markSeen(id);
    return true;
  }
}
