import 'package:dio/dio.dart';
import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/features/learning_checkpoint/models/learning_proposal_model.dart';
import 'package:facteur/features/learning_checkpoint/repositories/learning_checkpoint_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockApiClient extends Mock implements ApiClient {}

class FakeOptions extends Fake implements Options {}

void main() {
  late MockApiClient mockApi;
  late LearningCheckpointRepository repository;

  setUpAll(() {
    registerFallbackValue(FakeOptions());
  });

  setUp(() {
    mockApi = MockApiClient();
    repository = LearningCheckpointRepository(mockApi);
  });

  Map<String, dynamic> sampleJson({String id = 'p-1'}) => {
        'id': id,
        'proposal_type': 'source_priority',
        'entity_type': 'source',
        'entity_id': 'e-1',
        'entity_label': 'Le Monde',
        'current_value': 3,
        'proposed_value': 1,
        'signal_strength': 0.7,
        'signal_context': {
          'articles_shown': 15,
          'articles_clicked': 0,
          'articles_saved': 0,
          'period_days': 7,
        },
        'shown_count': 0,
        'status': 'pending',
      };

  group('fetchProposals', () {
    test('R1 — 200 + liste JSON → liste de LearningProposal', () async {
      when(() => mockApi.get(
            'learning-proposals',
            options: any(named: 'options'),
          )).thenAnswer((_) async => [sampleJson(), sampleJson(id: 'p-2')]);

      final result = await repository.fetchProposals();

      expect(result.length, 2);
      expect(result[0].id, 'p-1');
      expect(result[1].id, 'p-2');
    });

    test('R2 — 200 + liste vide', () async {
      when(() => mockApi.get(
            'learning-proposals',
            options: any(named: 'options'),
          )).thenAnswer((_) async => []);

      final result = await repository.fetchProposals();
      expect(result, isEmpty);
    });

    test('R3 — 404 → liste vide, pas d\'exception', () async {
      when(() => mockApi.get(
            'learning-proposals',
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 404),
      ));

      final result = await repository.fetchProposals();
      expect(result, isEmpty);
    });

    test('R4 — 500 → liste vide, log non-fatal', () async {
      when(() => mockApi.get(
            'learning-proposals',
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 500),
      ));

      final result = await repository.fetchProposals();
      expect(result, isEmpty);
    });

    test('R5 — timeout Dio → liste vide', () async {
      when(() => mockApi.get(
            'learning-proposals',
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        type: DioExceptionType.receiveTimeout,
      ));

      final result = await repository.fetchProposals();
      expect(result, isEmpty);
    });

    test('R5b — réponse non liste → liste vide', () async {
      when(() => mockApi.get(
            'learning-proposals',
            options: any(named: 'options'),
          )).thenAnswer((_) async => {'unexpected': 'shape'});

      final result = await repository.fetchProposals();
      expect(result, isEmpty);
    });
  });

  group('applyProposals', () {
    test('R6 — 200 → ApplyProposalsResponse OK', () async {
      when(() => mockApi.post(
            'apply-proposals',
            body: any(named: 'body'),
          )).thenAnswer((_) async => {'updated_preferences': []});

      final res = await repository.applyProposals(const [
        ApplyAction(proposalId: 'p-1', action: ApplyActionType.accept),
      ]);
      expect(res.updatedPreferences, isEmpty);
    });

    test('R7 — 500 → exception propagée', () async {
      when(() => mockApi.post(
            'apply-proposals',
            body: any(named: 'body'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 500),
      ));

      expect(
        () => repository.applyProposals(const [
          ApplyAction(proposalId: 'p-1', action: ApplyActionType.accept),
        ]),
        throwsA(isA<DioException>()),
      );
    });
  });
}
