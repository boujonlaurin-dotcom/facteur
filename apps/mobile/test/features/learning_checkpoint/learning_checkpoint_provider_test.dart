import 'package:dio/dio.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/features/learning_checkpoint/config/learning_checkpoint_flags.dart';
import 'package:facteur/features/learning_checkpoint/models/learning_proposal_model.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_cooldown_provider.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_provider.dart';
import 'package:facteur/features/learning_checkpoint/providers/learning_checkpoint_session_provider.dart';
import 'package:facteur/features/learning_checkpoint/repositories/learning_checkpoint_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockRepo extends Mock implements LearningCheckpointRepository {}

class MockAnalyticsService extends Mock implements AnalyticsService {}

class _FakeApplyAction extends Fake implements ApplyAction {}

LearningProposal makeProposal({
  String id = 'p-1',
  ProposalType type = ProposalType.sourcePriority,
  double signal = 0.7,
  num? currentValue = 3,
  num? proposedValue = 1,
}) {
  return LearningProposal(
    id: id,
    proposalType: type,
    entityType: EntityType.source,
    entityId: 'e-$id',
    entityLabel: 'Source $id',
    currentValue: currentValue,
    proposedValue: proposedValue,
    signalStrength: signal,
    signalContext: const SignalContext(articlesShown: 15),
    shownCount: 0,
    status: ProposalStatus.pending,
  );
}

Future<ProviderContainer> buildContainer({
  required MockRepo repo,
  bool cooldownActive = false,
  bool shownThisSession = false,
  MockAnalyticsService? analytics,
}) async {
  final analyticsMock = analytics ?? MockAnalyticsService();
  when(() => analyticsMock.trackEvent(any(), any()))
      .thenAnswer((_) async => Future.value());

  final container = ProviderContainer(
    overrides: [
      learningCheckpointRepositoryProvider.overrideWithValue(repo),
      learningCheckpointCooldownProvider
          .overrideWith((ref) async => cooldownActive),
      learningCheckpointShownThisSessionProvider
          .overrideWith((ref) => shownThisSession),
      analyticsServiceProvider.overrideWith((ref) => analyticsMock),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeApplyAction());
    registerFallbackValue(<ApplyAction>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('build() gating', () {
    test('G2 — cooldown actif → LcHidden, pas d\'appel repo', () async {
      final repo = MockRepo();
      final container =
          await buildContainer(repo: repo, cooldownActive: true);

      final state = await container.read(learningCheckpointProvider.future);
      expect(state, isA<LcHidden>());
      verifyNever(() => repo.fetchProposals());
    });

    test('G3 — déjà vu cette session → LcHidden', () async {
      final repo = MockRepo();
      final container =
          await buildContainer(repo: repo, shownThisSession: true);

      final state = await container.read(learningCheckpointProvider.future);
      expect(state, isA<LcHidden>());
      verifyNever(() => repo.fetchProposals());
    });

    test('G4 — < 3 propositions → LcHidden', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            makeProposal(id: 'p-1', signal: 0.9),
            makeProposal(id: 'p-2', signal: 0.8),
          ]);
      final container = await buildContainer(repo: repo);

      final state = await container.read(learningCheckpointProvider.future);
      expect(state, isA<LcHidden>());
    });

    test('G5 — 3+ mais max signal < 0.6 → LcHidden', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            makeProposal(id: 'p-1', signal: 0.5),
            makeProposal(id: 'p-2', signal: 0.4),
            makeProposal(id: 'p-3', signal: 0.3),
          ]);
      final container = await buildContainer(repo: repo);

      final state = await container.read(learningCheckpointProvider.future);
      expect(state, isA<LcHidden>());
    });

    test('G6 — 3 props + 1 signal ≥ 0.6 → LcVisible (3 triées DESC)',
        () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            makeProposal(id: 'p-1', signal: 0.5),
            makeProposal(id: 'p-2', signal: 0.75),
            makeProposal(id: 'p-3', signal: 0.6),
          ]);
      final container = await buildContainer(repo: repo);

      final state = await container.read(learningCheckpointProvider.future);
      expect(state, isA<LcVisible>());
      final visible = state as LcVisible;
      expect(visible.displayed.length, 3);
      expect(visible.displayed[0].id, 'p-2');
      expect(visible.displayed[1].id, 'p-3');
      expect(visible.displayed[2].id, 'p-1');
    });

    test('G7 — 7 propositions → LcVisible, displayed.length == 5', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            for (var i = 0; i < 7; i++)
              makeProposal(id: 'p-$i', signal: 0.6 + i * 0.05),
          ]);
      final container = await buildContainer(repo: repo);

      final state = await container.read(learningCheckpointProvider.future);
      expect(state, isA<LcVisible>());
      expect((state as LcVisible).displayed.length,
          LearningCheckpointFlags.maxProposalsDisplayed);
    });

    test('G8 — repo retourne [] → LcHidden', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => const []);
      final container = await buildContainer(repo: repo);

      final state = await container.read(learningCheckpointProvider.future);
      expect(state, isA<LcHidden>());
    });
  });

  group('actions', () {
    LearningProposal priorityProp(String id, {double signal = 0.7}) =>
        makeProposal(
          id: id,
          type: ProposalType.sourcePriority,
          signal: signal,
          currentValue: 3,
          proposedValue: 1,
        );

    test('G9 — dismissItem ajoute id dans dismissedIds', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            priorityProp('p-1', signal: 0.8),
            priorityProp('p-2'),
            priorityProp('p-3'),
          ]);
      final container = await buildContainer(repo: repo);
      await container.read(learningCheckpointProvider.future);

      final notifier = container.read(learningCheckpointProvider.notifier);
      notifier.dismissItem('p-2');

      final state = container.read(learningCheckpointProvider).value;
      expect(state, isA<LcVisible>());
      expect((state as LcVisible).dismissedIds, contains('p-2'));
    });

    test('G10 — dismiss tous les items → auto-snooze', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            priorityProp('p-1', signal: 0.8),
            priorityProp('p-2'),
            priorityProp('p-3'),
          ]);
      when(() => repo.applyProposals(any())).thenAnswer((_) async =>
          const ApplyProposalsResponse(updatedPreferences: []));

      final container = await buildContainer(repo: repo);
      await container.read(learningCheckpointProvider.future);

      final notifier = container.read(learningCheckpointProvider.notifier);
      notifier.dismissItem('p-1');
      notifier.dismissItem('p-2');
      // Le dernier dismiss déclenche snooze() automatiquement.
      notifier.dismissItem('p-3');

      // Attendre que snooze() async se termine.
      await Future<void>.delayed(Duration.zero);

      // Vérifie que applyProposals a été appelé (par snooze auto).
      verify(() => repo.applyProposals(any())).called(1);

      // État final = LcSnoozed (ou LcApplying → LcSnoozed).
      final state = container.read(learningCheckpointProvider).value;
      expect(state, anyOf(isA<LcSnoozed>(), isA<LcApplying>()));
    });

    test('G11 — modifyValue stocke la valeur', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            priorityProp('p-1', signal: 0.8),
            priorityProp('p-2'),
            priorityProp('p-3'),
          ]);
      final container = await buildContainer(repo: repo);
      await container.read(learningCheckpointProvider.future);

      container.read(learningCheckpointProvider.notifier).modifyValue('p-1', 2);

      final state = container.read(learningCheckpointProvider).value
          as LcVisible;
      expect(state.modifiedValues['p-1'], 2);
    });

    test('G12 — toggleExpanded ne garde qu\'une ligne ouverte', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            priorityProp('p-1', signal: 0.8),
            priorityProp('p-2'),
            priorityProp('p-3'),
          ]);
      final container = await buildContainer(repo: repo);
      await container.read(learningCheckpointProvider.future);

      final notifier = container.read(learningCheckpointProvider.notifier);
      notifier.toggleExpanded('p-1');
      var state = container.read(learningCheckpointProvider).value as LcVisible;
      expect(state.expandedRowId, 'p-1');

      notifier.toggleExpanded('p-2');
      state = container.read(learningCheckpointProvider).value as LcVisible;
      expect(state.expandedRowId, 'p-2');

      notifier.toggleExpanded('p-2');
      state = container.read(learningCheckpointProvider).value as LcVisible;
      expect(state.expandedRowId, isNull);
    });

    test('G13 — validate() succès : POST + cooldown + LcApplied', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            priorityProp('p-1', signal: 0.8),
            priorityProp('p-2'),
            priorityProp('p-3'),
            priorityProp('p-4'),
          ]);
      when(() => repo.applyProposals(any())).thenAnswer((_) async =>
          const ApplyProposalsResponse(updatedPreferences: []));

      final container = await buildContainer(repo: repo);
      await container.read(learningCheckpointProvider.future);

      final notifier = container.read(learningCheckpointProvider.notifier);
      notifier.dismissItem('p-2');
      notifier.modifyValue('p-1', 2);

      await notifier.validate();

      final captured =
          verify(() => repo.applyProposals(captureAny())).captured.single
              as List<ApplyAction>;

      expect(captured.length, 4);
      final byId = {for (final a in captured) a.proposalId: a};
      expect(byId['p-1']!.action, ApplyActionType.modify);
      expect(byId['p-1']!.value, 2);
      expect(byId['p-2']!.action, ApplyActionType.dismiss);
      expect(byId['p-3']!.action, ApplyActionType.accept);
      expect(byId['p-4']!.action, ApplyActionType.accept);

      expect(container.read(learningCheckpointProvider).value,
          isA<LcApplied>());

      // Cooldown posé.
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(LearningCheckpointFlags.kLastActionAtKey),
          isNotNull);
    });

    test('G14 — snooze() POST dismiss × N + cooldown + LcSnoozed', () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            priorityProp('p-1', signal: 0.8),
            priorityProp('p-2'),
            priorityProp('p-3'),
          ]);
      when(() => repo.applyProposals(any())).thenAnswer((_) async =>
          const ApplyProposalsResponse(updatedPreferences: []));

      final container = await buildContainer(repo: repo);
      await container.read(learningCheckpointProvider.future);

      await container.read(learningCheckpointProvider.notifier).snooze();

      final captured =
          verify(() => repo.applyProposals(captureAny())).captured.single
              as List<ApplyAction>;
      expect(captured.length, 3);
      expect(captured.every((a) => a.action == ApplyActionType.dismiss),
          isTrue);

      expect(container.read(learningCheckpointProvider).value,
          isA<LcSnoozed>());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(LearningCheckpointFlags.kLastActionAtKey),
          isNotNull);
    });

    test('G15 — validate() échec API → LcError, cooldown non posé',
        () async {
      final repo = MockRepo();
      when(() => repo.fetchProposals()).thenAnswer((_) async => [
            priorityProp('p-1', signal: 0.8),
            priorityProp('p-2'),
            priorityProp('p-3'),
          ]);
      when(() => repo.applyProposals(any())).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 500),
      ));

      final container = await buildContainer(repo: repo);
      await container.read(learningCheckpointProvider.future);

      await container.read(learningCheckpointProvider.notifier).validate();

      expect(
          container.read(learningCheckpointProvider).value, isA<LcError>());

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt(LearningCheckpointFlags.kLastActionAtKey), isNull);
    });
  });
}
