import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/learning_checkpoint_flags.dart';
import '../models/learning_proposal_model.dart';
import '../repositories/learning_checkpoint_repository.dart';
import '../services/learning_checkpoint_analytics.dart';
import 'learning_checkpoint_cooldown_provider.dart';
import 'learning_checkpoint_session_provider.dart';

@immutable
sealed class LearningCheckpointState {
  const LearningCheckpointState();

  /// Whether the card should occupy a slot in the feed.
  bool get shouldShow => false;
}

class LcHidden extends LearningCheckpointState {
  const LcHidden();
}

class LcVisible extends LearningCheckpointState {
  final List<LearningProposal> displayed;
  final Set<String> dismissedIds;
  final Map<String, num> modifiedValues;
  final String? expandedRowId;
  final Set<String> expandTrackedIds;
  final bool applying;
  final Object? error;

  const LcVisible({
    required this.displayed,
    this.dismissedIds = const {},
    this.modifiedValues = const {},
    this.expandedRowId,
    this.expandTrackedIds = const {},
    this.applying = false,
    this.error,
  });

  @override
  bool get shouldShow => true;

  bool get hasError => error != null;

  LcVisible copyWith({
    List<LearningProposal>? displayed,
    Set<String>? dismissedIds,
    Map<String, num>? modifiedValues,
    Object? expandedRowId = _sentinel,
    Set<String>? expandTrackedIds,
    bool? applying,
    Object? error = _sentinel,
  }) {
    return LcVisible(
      displayed: displayed ?? this.displayed,
      dismissedIds: dismissedIds ?? this.dismissedIds,
      modifiedValues: modifiedValues ?? this.modifiedValues,
      expandedRowId: identical(expandedRowId, _sentinel)
          ? this.expandedRowId
          : expandedRowId as String?,
      expandTrackedIds: expandTrackedIds ?? this.expandTrackedIds,
      applying: applying ?? this.applying,
      error: identical(error, _sentinel) ? this.error : error,
    );
  }
}

class LcApplied extends LearningCheckpointState {
  const LcApplied();
}

class LcSnoozed extends LearningCheckpointState {
  const LcSnoozed();
}

const _sentinel = Object();

class LearningCheckpointNotifier
    extends AsyncNotifier<LearningCheckpointState> {
  @override
  Future<LearningCheckpointState> build() async {
    if (!LearningCheckpointFlags.enabled) return const LcHidden();

    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(LearningCheckpointFlags.kForceDisabledKey) == true) {
      return const LcHidden();
    }

    // `read` (not `watch`) on cooldown: avoid rebuild after `_markCooldown()`
    // invalidates it — we want LcApplied/LcSnoozed to persist until an
    // explicit invalidate of this provider.
    final cooldownActive =
        await ref.read(learningCheckpointCooldownProvider.future);
    if (cooldownActive) return const LcHidden();

    final shownThisSession =
        ref.read(learningCheckpointShownThisSessionProvider);
    if (shownThisSession) return const LcHidden();

    final repo = ref.read(learningCheckpointRepositoryProvider);
    final all = await repo.fetchProposals();

    if (all.length < LearningCheckpointFlags.minProposals) {
      return const LcHidden();
    }
    final maxSignal = all
        .map((p) => p.signalStrength)
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (maxSignal < LearningCheckpointFlags.minSignalStrength) {
      return const LcHidden();
    }

    final sorted = [...all]
      ..sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
    final displayed =
        sorted.take(LearningCheckpointFlags.maxProposalsDisplayed).toList();

    Future.microtask(() {
      ref.read(learningCheckpointShownThisSessionProvider.notifier).state =
          true;
    });

    return LcVisible(displayed: displayed);
  }

  void toggleExpanded(String proposalId) {
    final current = state.valueOrNull;
    if (current is! LcVisible) return;
    final next = current.expandedRowId == proposalId ? null : proposalId;

    if (next != null && !current.expandTrackedIds.contains(proposalId)) {
      final proposal =
          current.displayed.firstWhere((p) => p.id == proposalId);
      ref
          .read(learningCheckpointAnalyticsProvider)
          .trackExpand(proposal);
      state = AsyncData(current.copyWith(
        expandedRowId: next,
        expandTrackedIds: {...current.expandTrackedIds, proposalId},
      ));
    } else {
      state = AsyncData(current.copyWith(expandedRowId: next));
    }
  }

  /// Dismiss a single proposal (✕). If it was the last → auto-snooze.
  void dismissItem(String proposalId) {
    final current = state.valueOrNull;
    if (current is! LcVisible) return;
    final proposal =
        current.displayed.where((p) => p.id == proposalId).firstOrNull;
    if (proposal == null) return;

    ref
        .read(learningCheckpointAnalyticsProvider)
        .trackDismissItem(proposal);

    final nextDismissed = {...current.dismissedIds, proposalId};
    final remaining =
        current.displayed.where((p) => !nextDismissed.contains(p.id)).length;

    state = AsyncData(current.copyWith(dismissedIds: nextDismissed));

    if (remaining <= 0) {
      // ignore: discarded_futures
      snooze();
    }
  }

  void modifyValue(String proposalId, num newValue) {
    final current = state.valueOrNull;
    if (current is! LcVisible) return;
    final nextMods = {...current.modifiedValues, proposalId: newValue};
    state = AsyncData(current.copyWith(modifiedValues: nextMods));
  }

  Future<void> validate() async {
    final current = state.valueOrNull;
    if (current is! LcVisible) return;

    final actions = <ApplyAction>[];
    int appliedCount = 0;
    int dismissedCount = 0;
    int modifiedCount = 0;

    for (final p in current.displayed) {
      if (current.dismissedIds.contains(p.id)) {
        actions.add(
          ApplyAction(proposalId: p.id, action: ApplyActionType.dismiss),
        );
        dismissedCount++;
      } else if (current.modifiedValues.containsKey(p.id)) {
        actions.add(
          ApplyAction(
            proposalId: p.id,
            action: ApplyActionType.modify,
            value: current.modifiedValues[p.id],
          ),
        );
        modifiedCount++;
      } else {
        actions.add(
          ApplyAction(proposalId: p.id, action: ApplyActionType.accept),
        );
        appliedCount++;
      }
    }

    state = AsyncData(current.copyWith(applying: true, error: null));

    try {
      final repo = ref.read(learningCheckpointRepositoryProvider);
      await repo.applyProposals(actions);

      await _markCooldown();

      ref.read(learningCheckpointAnalyticsProvider).trackValidate(
            applied: appliedCount,
            dismissed: dismissedCount,
            modified: modifiedCount,
            total: current.displayed.length,
          );

      state = const AsyncData(LcApplied());
    } catch (e, s) {
      debugPrint('LearningCheckpointNotifier.validate error: $e\n$s');
      state = AsyncData(current.copyWith(applying: false, error: e));
    }
  }

  Future<void> snooze() async {
    final current = state.valueOrNull;
    if (current is! LcVisible) return;

    final remaining = current.displayed
        .where((p) => !current.dismissedIds.contains(p.id))
        .toList();

    final actions = [
      for (final p in current.displayed)
        ApplyAction(proposalId: p.id, action: ApplyActionType.dismiss),
    ];

    state = AsyncData(current.copyWith(applying: true, error: null));

    try {
      final repo = ref.read(learningCheckpointRepositoryProvider);
      await repo.applyProposals(actions);

      await _markCooldown();

      ref
          .read(learningCheckpointAnalyticsProvider)
          .trackSnooze(pendingCount: remaining.length);

      state = const AsyncData(LcSnoozed());
    } catch (e, s) {
      debugPrint('LearningCheckpointNotifier.snooze error: $e\n$s');
      state = AsyncData(current.copyWith(applying: false, error: e));
    }
  }

  Future<void> _markCooldown() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(
      LearningCheckpointFlags.kLastActionAtKey,
      DateTime.now().millisecondsSinceEpoch,
    );
    ref.invalidate(learningCheckpointCooldownProvider);
  }
}

final learningCheckpointProvider = AsyncNotifierProvider<
    LearningCheckpointNotifier, LearningCheckpointState>(
  LearningCheckpointNotifier.new,
);
