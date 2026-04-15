import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/learning_checkpoint_flags.dart';
import '../models/learning_proposal_model.dart';
import '../repositories/learning_checkpoint_repository.dart';
import '../services/learning_checkpoint_analytics.dart';
import 'learning_checkpoint_cooldown_provider.dart';
import 'learning_checkpoint_session_provider.dart';

/// État sealed de la carte « Construire ton flux ».
@immutable
sealed class LearningCheckpointState {
  const LearningCheckpointState();
}

class LcHidden extends LearningCheckpointState {
  const LcHidden();
}

class LcVisible extends LearningCheckpointState {
  final List<LearningProposal> displayed;
  final Set<String> dismissedIds;
  final Map<String, num> modifiedValues;
  final String? expandedRowId;

  const LcVisible({
    required this.displayed,
    this.dismissedIds = const {},
    this.modifiedValues = const {},
    this.expandedRowId,
  });

  LcVisible copyWith({
    List<LearningProposal>? displayed,
    Set<String>? dismissedIds,
    Map<String, num>? modifiedValues,
    Object? expandedRowId = _sentinel,
  }) {
    return LcVisible(
      displayed: displayed ?? this.displayed,
      dismissedIds: dismissedIds ?? this.dismissedIds,
      modifiedValues: modifiedValues ?? this.modifiedValues,
      expandedRowId: identical(expandedRowId, _sentinel)
          ? this.expandedRowId
          : expandedRowId as String?,
    );
  }
}

class LcApplying extends LearningCheckpointState {
  final LcVisible previous;
  const LcApplying(this.previous);
}

class LcApplied extends LearningCheckpointState {
  const LcApplied();
}

class LcSnoozed extends LearningCheckpointState {
  const LcSnoozed();
}

class LcError extends LearningCheckpointState {
  final Object error;
  final LcVisible? previous;
  const LcError(this.error, {this.previous});
}

const _sentinel = Object();

class LearningCheckpointNotifier
    extends AsyncNotifier<LearningCheckpointState> {
  @override
  Future<LearningCheckpointState> build() async {
    // Kill-switch compilé.
    if (!LearningCheckpointFlags.enabled) return const LcHidden();

    // Override QA via SharedPreferences (dev/staging uniquement).
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(LearningCheckpointFlags.kForceDisabledKey) == true) {
      return const LcHidden();
    }

    // Cooldown 24h. `ref.read` (pas `watch`) pour ne pas rebuild le notifier
    // quand on invalide cooldown après `_markCooldown()` — on veut conserver
    // LcApplied / LcSnoozed jusqu'à une invalidation explicite du provider.
    final cooldownActive =
        await ref.read(learningCheckpointCooldownProvider.future);
    if (cooldownActive) return const LcHidden();

    // 1/session.
    final shownThisSession =
        ref.read(learningCheckpointShownThisSessionProvider);
    if (shownThisSession) return const LcHidden();

    // Fetch propositions.
    final repo = ref.read(learningCheckpointRepositoryProvider);
    final all = await repo.fetchProposals();

    // Gating pertinence.
    if (all.length < LearningCheckpointFlags.minProposals) {
      return const LcHidden();
    }
    final maxSignal = all
        .map((p) => p.signalStrength)
        .fold<double>(0, (a, b) => a > b ? a : b);
    if (maxSignal < LearningCheckpointFlags.minSignalStrength) {
      return const LcHidden();
    }

    // Tri DESC + troncature.
    final sorted = [...all]
      ..sort((a, b) => b.signalStrength.compareTo(a.signalStrength));
    final displayed =
        sorted.take(LearningCheckpointFlags.maxProposalsDisplayed).toList();

    // Marque « shown this session » pour éviter ré-affichage jusqu'au cold start.
    Future.microtask(() {
      // Côté-effet post-build pour éviter d'invalider pendant le build.
      ref.read(learningCheckpointShownThisSessionProvider.notifier).state =
          true;
    });

    return LcVisible(displayed: displayed);
  }

  /// Expand / collapse d'une ligne. Un seul panneau ouvert à la fois.
  void toggleExpanded(String proposalId) {
    final current = state.valueOrNull;
    if (current is! LcVisible) return;
    final next = current.expandedRowId == proposalId ? null : proposalId;
    state = AsyncData(current.copyWith(expandedRowId: next));

    if (next != null) {
      final proposal =
          current.displayed.firstWhere((p) => p.id == proposalId);
      ref
          .read(learningCheckpointAnalyticsProvider)
          .trackExpand(proposal);
    }
  }

  /// Dismiss individuel d'une proposition (✕).
  /// Si la dernière est dismiss → `snooze` automatique (cf. spec).
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

  /// Modifie la valeur proposée (slider source_priority).
  void modifyValue(String proposalId, num newValue) {
    final current = state.valueOrNull;
    if (current is! LcVisible) return;
    final nextMods = {...current.modifiedValues, proposalId: newValue};
    state = AsyncData(current.copyWith(modifiedValues: nextMods));
  }

  /// Valide l'ensemble des propositions : POST /apply-proposals.
  /// Accepte aussi LcError (retry) en restaurant l'état visible précédent.
  Future<void> validate() async {
    var current = state.valueOrNull;
    if (current is LcError) current = current.previous;
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

    state = AsyncData(LcApplying(current));

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
      state = AsyncData(LcError(e, previous: current));
    }
  }

  /// Reporte l'ensemble des propositions restantes (« Plus tard »).
  /// Accepte aussi LcError (retry) en restaurant l'état visible précédent.
  Future<void> snooze() async {
    var current = state.valueOrNull;
    if (current is LcError) current = current.previous;
    if (current is! LcVisible) return;

    final remaining = current.displayed
        .where((p) => !current.dismissedIds.contains(p.id))
        .toList();

    final actions = [
      for (final p in current.displayed)
        ApplyAction(proposalId: p.id, action: ApplyActionType.dismiss),
    ];

    state = AsyncData(LcApplying(current));

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
      state = AsyncData(LcError(e, previous: current));
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
