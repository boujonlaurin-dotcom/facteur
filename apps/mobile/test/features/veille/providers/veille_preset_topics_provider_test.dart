import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/api/providers.dart';
import 'package:facteur/features/veille/providers/veille_preset_topics_provider.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient api;
  late _MockDio dio;

  setUp(() {
    api = _MockApiClient();
    dio = _MockDio();
    when(() => api.dio).thenReturn(dio);
  });

  ProviderContainer makeContainer() {
    return ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(api)],
    );
  }

  Response<dynamic> profile(Map<String, double> subtopicWeights) {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: 'users/algorithm-profile'),
      statusCode: 200,
      data: {
        'interest_weights': const <String, double>{},
        'subtopic_weights': subtopicWeights,
        'source_affinities': const <String, double>{},
      },
    );
  }

  test('marks user-picked subtopics with "Suivi dans l\'app" and sorts them first',
      () async {
    when(() => dio.get<dynamic>('users/algorithm-profile')).thenAnswer(
      (_) async => profile({'ai': 1.4, 'gaming': 1.0}),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final topics =
        await container.read(veillePresetTopicsProvider('tech').future);

    expect(topics.length, greaterThan(2));
    final ai = topics.firstWhere((t) => t.id == 'ai');
    final gaming = topics.firstWhere((t) => t.id == 'gaming');
    final cyber = topics.firstWhere((t) => t.id == 'cybersecurity');
    expect(ai.reason, "Suivi dans l'app");
    expect(gaming.reason, "Suivi dans l'app");
    expect(cyber.reason, isNot("Suivi dans l'app"));
    // The label embeds the emoji so the UI doesn't need to look it up again.
    expect(ai.label, contains('Intelligence artificielle'));

    // Followed-in-app topics must appear before the rest of the list.
    final aiIdx = topics.indexWhere((t) => t.id == 'ai');
    final gamingIdx = topics.indexWhere((t) => t.id == 'gaming');
    final cyberIdx = topics.indexWhere((t) => t.id == 'cybersecurity');
    expect(aiIdx, lessThan(cyberIdx));
    expect(gamingIdx, lessThan(cyberIdx));
  });

  test('returns empty list for an unknown theme', () async {
    when(() => dio.get<dynamic>('users/algorithm-profile')).thenAnswer(
      (_) async => profile(const {}),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final topics = await container
        .read(veillePresetTopicsProvider('not-a-real-theme').future);

    expect(topics, isEmpty);
  });

  test('algorithm-profile failure → all subtopics marked as suggestions',
      () async {
    when(() => dio.get<dynamic>('users/algorithm-profile')).thenThrow(
      DioException(requestOptions: RequestOptions(path: 'users/algorithm-profile')),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final topics =
        await container.read(veillePresetTopicsProvider('science').future);

    expect(topics, isNotEmpty);
    expect(topics.every((t) => t.reason != "Suivi dans l'app"), isTrue);
  });
}
