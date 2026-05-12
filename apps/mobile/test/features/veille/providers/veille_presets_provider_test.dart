import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/api/providers.dart';
import 'package:facteur/features/veille/providers/veille_presets_provider.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _MockDio extends Mock implements Dio {}

void main() {
  late _MockApiClient api;
  late _MockDio dio;

  setUpAll(() {
    registerFallbackValue(<String, dynamic>{});
  });

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

  Response<dynamic> okResponse(List<Map<String, Object?>> rows) {
    return Response<dynamic>(
      requestOptions: RequestOptions(path: 'veille/presets'),
      statusCode: 200,
      data: rows,
    );
  }

  test('parses 3 presets from the API and exposes their fields', () async {
    when(() => dio.get<dynamic>('veille/presets')).thenAnswer(
      (_) async => okResponse([
        {
          'slug': 'ia_agentique',
          'label': 'Outils IA agentique',
          'accroche': 'Les derniers outils IA',
          'theme_id': 'tech',
          'theme_label': 'Technologie',
          'topics': ['Agents LLM', 'Frameworks'],
          'purposes': ['progresser_au_travail'],
          'editorial_brief': 'Plutôt analyses concrètes.',
          'sources': [
            {
              'id': 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa',
              'name': 'Source A',
              'url': 'https://a.example.com',
              'logo_url': null,
            },
          ],
        },
        {
          'slug': 'geopolitique_long',
          'label': 'Géopolitique long format',
          'accroche': 'Comprendre les recompositions',
          'theme_id': 'international',
          'theme_label': 'Géopolitique',
          'topics': [],
          'purposes': [],
          'editorial_brief': '',
          'sources': [],
        },
        {
          'slug': 'transition_climat',
          'label': 'Transition climatique',
          'accroche': 'Suivre la transition',
          'theme_id': 'environment',
          'theme_label': 'Environnement',
          'topics': ['Politiques publiques'],
          'purposes': ['preparer_projet'],
          'editorial_brief': 'Articles factuels',
          'sources': [],
        },
      ]),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final presets = await container.read(veillePresetsProvider.future);

    expect(presets.length, 3);
    expect(presets[0].slug, 'ia_agentique');
    expect(presets[0].label, 'Outils IA agentique');
    expect(presets[0].themeId, 'tech');
    expect(presets[0].topics, ['Agents LLM', 'Frameworks']);
    expect(presets[0].purposes, ['progresser_au_travail']);
    expect(presets[0].sources.length, 1);
    expect(presets[0].sources.first.name, 'Source A');

    expect(presets[1].slug, 'geopolitique_long');
    expect(presets[1].sources, isEmpty);

    expect(presets[2].editorialBrief, 'Articles factuels');
  });

  test('falls back to empty list when the API throws', () async {
    when(() => dio.get<dynamic>('veille/presets')).thenThrow(
      DioException(requestOptions: RequestOptions(path: 'veille/presets')),
    );

    final container = makeContainer();
    addTearDown(container.dispose);
    final presets = await container.read(veillePresetsProvider.future);

    expect(presets, isEmpty);
  });
}
