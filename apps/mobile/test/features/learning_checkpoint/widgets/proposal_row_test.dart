import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/learning_checkpoint/models/learning_proposal_model.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_cooldown_provider.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_provider.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_session_provider.dart';
import 'package:facteur/features/learning_checkpoint/repositories/learning_checkpoint_repository.dart';
import 'package:facteur/features/learning_checkpoint/widgets/entity_toggle.dart';
import 'package:facteur/features/learning_checkpoint/widgets/proposal_row.dart';
import 'package:facteur/features/learning_checkpoint/widgets/proposal_stats_panel.dart';
import 'package:facteur/features/learning_checkpoint/widgets/source_priority_slider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockRepo extends Mock implements LearningCheckpointRepository {}

class MockAnalyticsService extends Mock implements AnalyticsService {}

LearningProposal makeProposal({
  required String id,
  required ProposalType type,
  double signal = 0.8,
}) =>
    LearningProposal(
      id: id,
      proposalType: type,
      entityType: EntityType.source,
      entityId: 'e-$id',
      entityLabel: 'Entity $id',
      currentValue: type == ProposalType.sourcePriority ? 3 : null,
      proposedValue: type == ProposalType.sourcePriority ? 1 : null,
      signalStrength: signal,
      signalContext: const SignalContext(articlesShown: 10),
      shownCount: 0,
      status: ProposalStatus.pending,
    );

Widget wrap(ProviderContainer container, Widget child) =>
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(body: child),
      ),
    );

ProviderContainer makeContainer({List<LearningProposal>? proposals}) {
  final repo = MockRepo();
  when(() => repo.fetchProposals())
      .thenAnswer((_) async => proposals ?? const []);
  final svc = MockAnalyticsService();
  when(() => svc.trackEvent(any(), any()))
      .thenAnswer((_) async => Future.value());
  return ProviderContainer(overrides: [
    learningCheckpointRepositoryProvider.overrideWithValue(repo),
    learningCheckpointCooldownProvider.overrideWith((ref) async => false),
    learningCheckpointShownThisSessionProvider.overrideWith((ref) => false),
    analyticsServiceProvider.overrideWith((ref) => svc),
  ]);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('P1 — source_priority : rend SourcePrioritySlider',
      (tester) async {
    final proposal = makeProposal(id: 'p-1', type: ProposalType.sourcePriority);
    final container = makeContainer(proposals: [proposal]);
    addTearDown(container.dispose);
    await container.read(learningCheckpointProvider.future);

    await tester.pumpWidget(wrap(container, ProposalRow(proposal: proposal)));
    await tester.pumpAndSettle();

    expect(find.byType(SourcePrioritySlider), findsOneWidget);
  });

  testWidgets('P2 — mute_entity : rend EntityToggle (mute)', (tester) async {
    final proposal = makeProposal(id: 'p-1', type: ProposalType.muteEntity);
    final container = makeContainer(proposals: [proposal]);
    addTearDown(container.dispose);
    await container.read(learningCheckpointProvider.future);

    await tester.pumpWidget(wrap(container, ProposalRow(proposal: proposal)));
    await tester.pumpAndSettle();

    expect(find.byType(EntityToggle), findsOneWidget);
    expect(find.text('Masquer'), findsOneWidget);
  });

  testWidgets('P3 — follow_entity : rend EntityToggle (follow)',
      (tester) async {
    final proposal = makeProposal(id: 'p-1', type: ProposalType.followEntity);
    final container = makeContainer(proposals: [proposal]);
    addTearDown(container.dispose);
    await container.read(learningCheckpointProvider.future);

    await tester.pumpWidget(wrap(container, ProposalRow(proposal: proposal)));
    await tester.pumpAndSettle();

    expect(find.byType(EntityToggle), findsOneWidget);
    expect(find.text('Suivre'), findsOneWidget);
  });

  testWidgets('P6 — isExpanded : affiche ProposalStatsPanel', (tester) async {
    final proposal = makeProposal(id: 'p-1', type: ProposalType.sourcePriority);
    final container = makeContainer(proposals: [proposal]);
    addTearDown(container.dispose);
    await container.read(learningCheckpointProvider.future);

    await tester.pumpWidget(wrap(
      container,
      ProposalRow(proposal: proposal, isExpanded: true),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(ProposalStatsPanel), findsOneWidget);
  });

  testWidgets('P7 — Semantics : label "Ignorer cette proposition" présent',
      (tester) async {
    final proposal = makeProposal(id: 'p-1', type: ProposalType.sourcePriority);
    final container = makeContainer(proposals: [proposal]);
    addTearDown(container.dispose);
    await container.read(learningCheckpointProvider.future);

    await tester.pumpWidget(wrap(container, ProposalRow(proposal: proposal)));
    await tester.pumpAndSettle();

    expect(find.bySemanticsLabel('Ignorer cette proposition'), findsOneWidget);
  });
}
