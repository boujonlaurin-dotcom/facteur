import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dio/dio.dart';
import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/features/custom_topics/repositories/topic_repository.dart';

class MockApiClient extends Mock implements ApiClient {}

void main() {
  late MockApiClient mockApiClient;
  late TopicRepository repository;

  setUp(() {
    mockApiClient = MockApiClient();
    repository = TopicRepository(mockApiClient);
  });

  group('getTopics', () {
    test('returns list of UserTopicProfile on success', () async {
      when(() => mockApiClient.get(
            'personalization/topics/',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => [
            {'id': 'uuid-1', 'topic_name': 'IA', 'priority_multiplier': 1.0},
            {
              'id': 'uuid-2',
              'topic_name': 'Climate',
              'priority_multiplier': 1.5,
              'slug_parent': 'climate'
            },
          ]);

      final result = await repository.getTopics();

      expect(result.length, 2);
      expect(result[0].name, 'IA');
      expect(result[0].priorityMultiplier, 1.0);
      expect(result[1].name, 'Climate');
      expect(result[1].slugParent, 'climate');
    });

    test('returns empty list when response is not a list', () async {
      when(() => mockApiClient.get(
            'personalization/topics/',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => {'error': 'unexpected format'});

      final result = await repository.getTopics();
      expect(result, isEmpty);
    });

    test('returns empty list for empty array', () async {
      when(() => mockApiClient.get(
            'personalization/topics/',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => []);

      final result = await repository.getTopics();
      expect(result, isEmpty);
    });

    test('rethrows DioException on API failure', () async {
      when(() => mockApiClient.get(
            'personalization/topics/',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 500),
      ));

      expect(() => repository.getTopics(), throwsA(isA<DioException>()));
    });
  });

  group('followTopic', () {
    test('returns LLM-enriched UserTopicProfile on success', () async {
      when(() => mockApiClient.post(
            'personalization/topics/',
            body: {'name': 'Mobilite douce'},
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => {
            'id': 'uuid-new',
            'topic_name': 'Mobilite douce',
            'slug_parent': 'climate',
            'keywords': ['velo', 'transport'],
            'intent_description': 'Suivi actualites mobilite',
            'priority_multiplier': 1.0,
          });

      final result = await repository.followTopic('Mobilite douce');

      expect(result.id, 'uuid-new');
      expect(result.name, 'Mobilite douce');
      expect(result.slugParent, 'climate');
      expect(result.keywords, ['velo', 'transport']);
      expect(result.intentDescription, 'Suivi actualites mobilite');
    });

    test('rethrows DioException on 409 conflict (duplicate)', () async {
      when(() => mockApiClient.post(
            'personalization/topics/',
            body: {'name': 'IA'},
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response: Response(
          requestOptions: RequestOptions(path: ''),
          statusCode: 409,
          data: {'detail': 'Topic already followed'},
        ),
      ));

      expect(
          () => repository.followTopic('IA'), throwsA(isA<DioException>()));
    });
  });

  group('updateTopicPriority', () {
    test('returns updated UserTopicProfile', () async {
      when(() => mockApiClient.put(
            'personalization/topics/uuid-1',
            body: {'priority_multiplier': 2.0},
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => {
            'id': 'uuid-1',
            'topic_name': 'IA',
            'priority_multiplier': 2.0,
            'composite_score': 10,
          });

      final result = await repository.updateTopicPriority('uuid-1', 2.0);

      expect(result.id, 'uuid-1');
      expect(result.priorityMultiplier, 2.0);
      expect(result.compositeScore, 10);
    });

    test('rethrows DioException on 404 (topic not found)', () async {
      when(() => mockApiClient.put(
            'personalization/topics/non-existent',
            body: {'priority_multiplier': 1.0},
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 404),
      ));

      expect(() => repository.updateTopicPriority('non-existent', 1.0),
          throwsA(isA<DioException>()));
    });
  });

  group('unfollowTopic', () {
    test('completes without error on 200', () async {
      when(() => mockApiClient.delete(
            'personalization/topics/uuid-1',
            body: any<dynamic>(named: 'body'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => null);

      await expectLater(repository.unfollowTopic('uuid-1'), completes);
    });

    test('rethrows DioException on failure', () async {
      when(() => mockApiClient.delete(
            'personalization/topics/uuid-1',
            body: any<dynamic>(named: 'body'),
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 500),
      ));

      expect(() => repository.unfollowTopic('uuid-1'),
          throwsA(isA<DioException>()));
    });
  });

  group('getTopicSuggestions', () {
    test('returns list of suggestion labels with theme filter', () async {
      when(() => mockApiClient.get(
            'personalization/topics/suggestions',
            queryParameters: {'theme': 'tech'},
            options: any(named: 'options'),
          )).thenAnswer((_) async => [
            {'slug': 'ai', 'label': 'Intelligence artificielle', 'article_count': 5},
            {'slug': 'cybersecurity', 'label': 'Cybersecurite', 'article_count': 3},
            {'slug': 'startups', 'label': 'Startups', 'article_count': 2},
          ]);

      final result = await repository.getTopicSuggestions(theme: 'tech');

      expect(result, ['Intelligence artificielle', 'Cybersecurite', 'Startups']);
    });

    test('returns list without theme filter', () async {
      when(() => mockApiClient.get(
            'personalization/topics/suggestions',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => [
            {'slug': 'ai', 'label': 'IA', 'article_count': 10},
            {'slug': 'climate', 'label': 'Climat', 'article_count': 7},
          ]);

      final result = await repository.getTopicSuggestions();

      expect(result.length, 2);
      expect(result[0], 'IA');
      expect(result[1], 'Climat');
    });

    test('returns empty list on non-list response', () async {
      when(() => mockApiClient.get(
            'personalization/topics/suggestions',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => {'error': 'not a list'});

      final result = await repository.getTopicSuggestions(theme: 'tech');
      expect(result, isEmpty);
    });

    test('returns empty list on DioException (graceful degradation)', () async {
      when(() => mockApiClient.get(
            'personalization/topics/suggestions',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenThrow(DioException(
        requestOptions: RequestOptions(path: ''),
        response:
            Response(requestOptions: RequestOptions(path: ''), statusCode: 500),
      ));

      final result = await repository.getTopicSuggestions(theme: 'tech');
      expect(result, isEmpty);
    });

    test('returns empty list for empty array response', () async {
      when(() => mockApiClient.get(
            'personalization/topics/suggestions',
            queryParameters: any(named: 'queryParameters'),
            options: any(named: 'options'),
          )).thenAnswer((_) async => []);

      final result = await repository.getTopicSuggestions(theme: 'tech');
      expect(result, isEmpty);
    });
  });
}
