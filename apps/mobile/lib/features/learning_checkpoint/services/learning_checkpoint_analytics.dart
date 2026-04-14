import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/analytics_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../models/learning_proposal_model.dart';

/// Wrapper centralisant les 5 événements analytics de la carte
/// « Construire ton flux » (Epic 13).
///
/// Événements :
/// - `construire_flux.shown`
/// - `construire_flux.expand`
/// - `construire_flux.dismiss_item`
/// - `construire_flux.validate`
/// - `construire_flux.snooze`
class LearningCheckpointAnalytics {
  final AnalyticsService _svc;

  LearningCheckpointAnalytics(this._svc);

  void trackShown(List<LearningProposal> displayed) {
    final maxSignal = displayed.isEmpty
        ? 0.0
        : displayed
            .map((p) => p.signalStrength)
            .reduce((a, b) => a > b ? a : b);
    _svc.trackEvent('construire_flux.shown', {
      'proposals_count': displayed.length,
      'types': displayed.map((p) => p.proposalType.toWire()).toList(),
      'max_signal_strength': maxSignal,
    });
  }

  void trackExpand(LearningProposal proposal) {
    _svc.trackEvent('construire_flux.expand', {
      'proposal_id': proposal.id,
      'proposal_type': proposal.proposalType.toWire(),
      'signal_strength': proposal.signalStrength,
    });
  }

  void trackDismissItem(LearningProposal proposal) {
    _svc.trackEvent('construire_flux.dismiss_item', {
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
    _svc.trackEvent('construire_flux.validate', {
      'applied_count': applied,
      'dismissed_count': dismissed,
      'modified_count': modified,
      'total_presented': total,
    });
  }

  void trackSnooze({required int pendingCount}) {
    _svc.trackEvent('construire_flux.snooze', {
      'pending_count': pendingCount,
    });
  }
}

final learningCheckpointAnalyticsProvider =
    Provider<LearningCheckpointAnalytics>((ref) {
  return LearningCheckpointAnalytics(ref.read(analyticsServiceProvider));
});
