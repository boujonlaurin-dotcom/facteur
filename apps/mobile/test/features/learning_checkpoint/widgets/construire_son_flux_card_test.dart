import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/learning_checkpoint/models/learning_proposal_model.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_cooldown_provider.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_provider.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_session_provider.dart';
import 'package:facteur/features/learning_checkpoint/repositories/learning_checkpoint_repository.dart';
import 'package:facteur/features/learning_checkpoint/widgets/construire_son_flux_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockRepo extends Mock implements LearningCheckpointRepository {}

class MockAnalyticsService extends Mock implements AnalyticsService {}

class _FakeApplyAction extends Fake implements ApplyAction {}

LearningProposal makeProposal(String id, {double signal = 0.7}) =>
    LearningProposal(
      id: id,
      proposalType: ProposalType.sourcePriority,
      entityType: EntityType.source,
      entityId: 'e-$id',
      entityLabel: 'Source $id',
      currentValue: 3,
      proposedValue: 1,
      signalStrength: signal,
      signalContext: const SignalContext(articlesShown: 10),
      shownCount: 0,
      status: ProposalStatus.pending,
    );

Widget buildApp(ProviderContainer container, Widget child) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

ProviderContainer makeContainer({
  required MockRepo repo,
  MockAnalyticsService? analytics,
  bool cooldownActive = false,
  bool shownThisSession = false,
}) {
  final svc = analytics ?? MockAnalyticsService();
  when(() => svc.trackEvent(any(), any()))
      .thenAnswer((_) async => Future.value());
  return ProviderContainer(
    overrides: [
      learningCheckpointRepositoryProvider.overrideWithValue(repo),
      learningCheckpointCooldownProvider
          .overrideWith((ref) async => cooldownActive),
      learningCheckpointShownThisSessionProvider
          .overrideWith((ref) => shownThisSession),
      analyticsServiceProvider.overrideWith((ref) => svc),
    ],
  );
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeApplyAction());
    registerFallbackValue(<ApplyAction>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('W1 — LcHidden : SizedBox.shrink', (tester) async {
    final repo = MockRepo();
    when(() => repo.fetchProposals()).thenAnswer((_) async => const []);
    final container = makeContainer(repo: repo);
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container, const ConstruireSonFluxCard()));
    await tester.pumpAndSettle();

    expect(find.text('Construire ton flux · Cette semaine'), findsNothing);
  });

  testWidgets('W3 — LcVisible avec 3 props : header + rows + footer',
      (tester) async {
    final repo = MockRepo();
    when(() => repo.fetchProposals()).thenAnswer((_) async => [
          makeProposal('p-1', signal: 0.8),
          makeProposal('p-2', signal: 0.7),
          makeProposal('p-3', signal: 0.65),
        ]);
    final container = makeContainer(repo: repo);
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container, const ConstruireSonFluxCard()));
    await tester.pumpAndSettle();

    expect(find.text('Construire ton flux · Cette semaine'), findsOneWidget);
    expect(find.text('Source p-1'), findsOneWidget);
    expect(find.text('Source p-2'), findsOneWidget);
    expect(find.text('Source p-3'), findsOneWidget);
    expect(find.text('Valider'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
  });

  testWidgets('W4 — tap « Valider » appelle validate() → LcApplied',
      (tester) async {
    final repo = MockRepo();
    when(() => repo.fetchProposals()).thenAnswer((_) async => [
          makeProposal('p-1', signal: 0.8),
          makeProposal('p-2', signal: 0.7),
          makeProposal('p-3', signal: 0.65),
        ]);
    when(() => repo.applyProposals(any())).thenAnswer((_) async =>
        const ApplyProposalsResponse(updatedPreferences: []));

    final container = makeContainer(repo: repo);
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container, const ConstruireSonFluxCard()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Valider'));
    await tester.pumpAndSettle();

    verify(() => repo.applyProposals(any())).called(1);
    expect(container.read(learningCheckpointProvider).value,
        isA<LcApplied>());
  });

  testWidgets('W5 — tap « Plus tard » appelle snooze() → LcSnoozed',
      (tester) async {
    final repo = MockRepo();
    when(() => repo.fetchProposals()).thenAnswer((_) async => [
          makeProposal('p-1', signal: 0.8),
          makeProposal('p-2', signal: 0.7),
          makeProposal('p-3', signal: 0.65),
        ]);
    when(() => repo.applyProposals(any())).thenAnswer((_) async =>
        const ApplyProposalsResponse(updatedPreferences: []));

    final container = makeContainer(repo: repo);
    addTearDown(container.dispose);

    await tester.pumpWidget(buildApp(container, const ConstruireSonFluxCard()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();

    verify(() => repo.applyProposals(any())).called(1);
    expect(container.read(learningCheckpointProvider).value,
        isA<LcSnoozed>());
  });
}
