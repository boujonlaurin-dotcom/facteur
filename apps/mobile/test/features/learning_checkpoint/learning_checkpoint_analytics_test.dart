import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/learning_checkpoint/models/learning_proposal_model.dart';
import 'package:facteur/features/learning_checkpoint/services/learning_checkpoint_analytics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAnalyticsService extends Mock implements AnalyticsService {}

void main() {
  late MockAnalyticsService mockSvc;
  late LearningCheckpointAnalytics analytics;

  LearningProposal makeProposal({
    String id = 'p-1',
    ProposalType type = ProposalType.sourcePriority,
    double signal = 0.7,
  }) {
    return LearningProposal(
      id: id,
      proposalType: type,
      entityType: EntityType.source,
      entityId: 'e-1',
      entityLabel: 'Le Monde',
      currentValue: 3,
      proposedValue: 1,
      signalStrength: signal,
      signalContext: const SignalContext(),
    );
  }

  setUp(() {
    mockSvc = MockAnalyticsService();
    when(() => mockSvc.trackEvent(any(), any()))
        .thenAnswer((_) async => Future.value());
    analytics = LearningCheckpointAnalytics(mockSvc);
  });

  test('trackShown émet construire_flux.shown avec propriétés agrégées', () {
    analytics.trackShown([
      makeProposal(signal: 0.7),
      makeProposal(id: 'p-2', type: ProposalType.followEntity, signal: 0.9),
    ]);

    final captured =
        verify(() => mockSvc.trackEvent('construire_flux.shown', captureAny()))
            .captured
            .single as Map<String, dynamic>;
    expect(captured['proposals_count'], 2);
    expect(captured['max_signal_strength'], closeTo(0.9, 1e-6));
    expect(captured['types'], ['source_priority', 'follow_entity']);
  });

  test('trackExpand émet construire_flux.expand', () {
    analytics.trackExpand(makeProposal(id: 'p-7', signal: 0.65));

    final captured =
        verify(() => mockSvc.trackEvent('construire_flux.expand', captureAny()))
            .captured
            .single as Map<String, dynamic>;
    expect(captured['proposal_id'], 'p-7');
    expect(captured['proposal_type'], 'source_priority');
    expect(captured['signal_strength'], closeTo(0.65, 1e-6));
  });

  test('trackDismissItem émet construire_flux.dismiss_item', () {
    analytics.trackDismissItem(makeProposal(id: 'p-3'));

    final captured = verify(() =>
            mockSvc.trackEvent('construire_flux.dismiss_item', captureAny()))
        .captured
        .single as Map<String, dynamic>;
    expect(captured['proposal_id'], 'p-3');
    expect(captured['proposal_type'], 'source_priority');
  });

  test('trackValidate émet construire_flux.validate avec compteurs', () {
    analytics.trackValidate(
        applied: 2, dismissed: 1, modified: 1, total: 4);

    final captured = verify(
            () => mockSvc.trackEvent('construire_flux.validate', captureAny()))
        .captured
        .single as Map<String, dynamic>;
    expect(captured['applied_count'], 2);
    expect(captured['dismissed_count'], 1);
    expect(captured['modified_count'], 1);
    expect(captured['total_presented'], 4);
  });

  test('trackSnooze émet construire_flux.snooze avec pending_count', () {
    analytics.trackSnooze(pendingCount: 3);

    final captured =
        verify(() => mockSvc.trackEvent('construire_flux.snooze', captureAny()))
            .captured
            .single as Map<String, dynamic>;
    expect(captured['pending_count'], 3);
  });
}
