import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/analytics_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../models/learning_proposal_model.dart';

abstract class LcEvents {
  static const shown = 'construire_flux.shown';
  static const expand = 'construire_flux.expand';
  static const dismissItem = 'construire_flux.dismiss_item';
  static const validate = 'construire_flux.validate';
  static const snooze = 'construire_flux.snooze';
}

/// Wraps AnalyticsService for the « Construire ton flux » card and dedupes
/// `shown` (once per provider lifetime) + `expand` (once per proposal).
/// Provider-scoped instance: a fresh Set is created on each provider rebuild
/// (cold start, pull-to-refresh) — naturally session-scoped.
class LearningCheckpointAnalytics {
  final AnalyticsService _svc;
  bool _shownTracked = false;
  final Set<String> _expandTracked = {};

  LearningCheckpointAnalytics(this._svc);

  void trackShown(List<LearningProposal> displayed) {
    if (_shownTracked) return;
    _shownTracked = true;
    final maxSignal = displayed.isEmpty
        ? 0.0
        : displayed
            .map((p) => p.signalStrength)
            .reduce((a, b) => a > b ? a : b);
    _svc.trackEvent(LcEvents.shown, {
      'proposals_count': displayed.length,
      'types': displayed.map((p) => p.proposalType.toWire()).toList(),
      'max_signal_strength': maxSignal,
    });
  }

  void trackExpand(LearningProposal proposal) {
    if (!_expandTracked.add(proposal.id)) return;
    _svc.trackEvent(LcEvents.expand, {
      'proposal_id': proposal.id,
      'proposal_type': proposal.proposalType.toWire(),
      'signal_strength': proposal.signalStrength,
    });
  }

  void trackDismissItem(LearningProposal proposal) {
    _svc.trackEvent(LcEvents.dismissItem, {
      'proposal_id': proposal.id,
      'proposal_type': proposal.proposalType.toWire(),
    });
  }

  void trackValidate({
    required int applied,
    required int dismissed,
    required int modified,
    required int total,
  }) {
    _svc.trackEvent(LcEvents.validate, {
      'applied_count': applied,
      'dismissed_count': dismissed,
      'modified_count': modified,
      'total_presented': total,
    });
  }

  void trackSnooze({required int pendingCount}) {
    _svc.trackEvent(LcEvents.snooze, {
      'pending_count': pendingCount,
    });
  }
}

final learningCheckpointAnalyticsProvider =
    Provider<LearningCheckpointAnalytics>((ref) {
  return LearningCheckpointAnalytics(ref.read(analyticsServiceProvider));
});
