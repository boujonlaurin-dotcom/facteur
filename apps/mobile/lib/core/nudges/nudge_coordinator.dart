import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'nudge.dart';
import 'nudge_events.dart';
import 'nudge_registry.dart';
import 'nudge_service.dart';
import 'nudges_enabled_provider.dart';

/// Global cooldown enforced between any two non-critical nudges.
const Duration kGlobalNonCriticalCooldown = Duration(hours: 24);

/// Maximum number of `normal`/`low` nudges per app session.
const int kSessionNonCriticalBudget = 1;

/// Coordinates which nudge is currently shown, enforcing queue order,
/// priority, prerequisites, per-session budget and global cooldown.
///
/// State is in-memory and reset on app restart. Persistent per-nudge state
/// (seen, lastShown) lives in [NudgeStorage] via [NudgeService].
class NudgeCoordinator {
  NudgeCoordinator({
    NudgeService? service,
    DateTime Function()? clock,
    Future<bool> Function()? isEnabled,
    NudgeEvents? events,
  })  : _service = service ?? NudgeService(clock: clock),
        _clock = clock ?? DateTime.now,
        _isEnabled = isEnabled ?? (() async => true),
        _events = events;

  final NudgeService _service;
  final DateTime Function() _clock;
  final Future<bool> Function() _isEnabled;
  final NudgeEvents? _events;

  final List<String> _queue = [];
  final ValueNotifier<String?> _activeNotifier = ValueNotifier<String?>(null);
  int _sessionNonCriticalShown = 0;
  DateTime? _lastNonCriticalAt;

  String? get activeId => _activeNotifier.value;
  List<String> get queuedIds => List.unmodifiable(_queue);

  /// Listenable for widgets that need to rebuild on active-nudge changes.
  ValueListenable<String?> get activeListenable => _activeNotifier;

  String? get _active => _activeNotifier.value;
  set _active(String? v) => _activeNotifier.value = v;

  /// Request that a nudge be shown. Returns the id of the nudge that
  /// *actually* became active (may be null, or a different id if an earlier
  /// request was already queued and higher-priority).
  Future<String?> request(String id) async {
    if (!await _eligible(id)) return _active;
    final previousActive = _active;
    if (_active == null) {
      _active = id;
      await _emitShown(_active!);
      return _active;
    }
    if (_queue.contains(id) || _active == id) return _active;
    _queue.add(id);
    _sortQueue();
    // If the queued nudge outranks the active one, preempt.
    final topId = _queue.first;
    if (_priorityRank(topId) < _priorityRank(_active!)) {
      _queue.removeAt(0);
      _queue.add(_active!);
      _sortQueue();
      _active = topId;
      if (_active != previousActive) {
        await _emitShown(_active!);
      }
    }
    return _active;
  }

  /// Mark the currently active nudge as dismissed (optionally as seen).
  /// Advances the queue to the next eligible nudge.
  Future<String?> dismiss({required bool markSeen}) async {
    return _dismiss(outcome: 'dismissed', markSeen: markSeen);
  }

  /// Dismiss the active nudge and report it as a conversion (user took the
  /// action the nudge was suggesting). Always marks seen.
  Future<String?> markConverted(String id) async {
    if (_active != id) return _active;
    return _dismiss(outcome: 'converted', markSeen: true);
  }

  Future<String?> _dismiss({
    required String outcome,
    required bool markSeen,
  }) async {
    final closing = _active;
    if (closing == null) return null;
    final nudge = NudgeRegistry.get(closing);
    if (markSeen && nudge.frequency == NudgeFrequency.once) {
      await _service.markSeen(closing);
    } else {
      await _service.markShown(closing);
    }
    if (nudge.consumesSessionBudget) {
      _sessionNonCriticalShown += 1;
      _lastNonCriticalAt = _clock();
    }
    await _events?.dismissed(closing, outcome: outcome);
    _active = null;
    await _advance();
    if (_active != null) {
      await _emitShown(_active!);
    }
    return _active;
  }

  Future<void> _advance() async {
    while (_queue.isNotEmpty) {
      final next = _queue.removeAt(0);
      if (await _eligible(next)) {
        _active = next;
        return;
      }
    }
  }

  Future<bool> _eligible(String id) async {
    final nudge = NudgeRegistry.get(id);

    if (nudge.priority != NudgePriority.critical && !await _isEnabled()) {
      return false;
    }

    if (!await _service.canShow(id)) return false;

    for (final prereqId in nudge.prerequisites) {
      if (NudgeRegistry.has(prereqId)) {
        final seen = await _service.isSeen(prereqId);
        if (!seen) return false;
      }
    }

    if (nudge.consumesSessionBudget) {
      if (_sessionNonCriticalShown >= kSessionNonCriticalBudget) return false;
      if (_lastNonCriticalAt != null) {
        final since = _clock().difference(_lastNonCriticalAt!);
        if (since < kGlobalNonCriticalCooldown) return false;
      }
    }

    return true;
  }

  Future<void> _emitShown(String id) async {
    await _events?.shown(id);
  }

  /// Rank used for queue sort. Lower is higher priority.
  int _priorityRank(String id) => NudgeRegistry.get(id).priority.index;

  void _sortQueue() {
    _queue.sort((a, b) => _priorityRank(a).compareTo(_priorityRank(b)));
  }

  /// Test helper — reset in-memory state without touching persistence.
  void resetSession() {
    _queue.clear();
    _active = null;
    _sessionNonCriticalShown = 0;
    _lastNonCriticalAt = null;
  }
}

final nudgeServiceProvider = Provider<NudgeService>((ref) {
  return NudgeService();
});

final nudgeCoordinatorProvider = Provider<NudgeCoordinator>((ref) {
  return NudgeCoordinator(
    service: ref.watch(nudgeServiceProvider),
    events: ref.watch(nudgeEventsProvider),
    isEnabled: () async {
      try {
        return await ref.read(nudgesEnabledProvider.future);
      } catch (_) {
        return true;
      }
    },
  );
});
