import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/providers/veille_source_suggestions_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';

class _FakeRepo implements VeilleRepository {
  final List<VeilleSourceSuggestionDto> sources;
  final Object? error;
  List<String>? capturedAngles;
  List<String>? capturedKeywords;

  _FakeRepo(this.sources, {this.error});

  @override
  Future<List<VeilleSourceSuggestionDto>> suggestSources({
    required String themeId,
    required String themeLabel,
    String brief = '',
    List<String> angles = const [],
    List<String> keywords = const [],
  }) async {
    capturedAngles = angles;
    capturedKeywords = keywords;
    final err = error;
    if (err != null) throw err;
    return sources;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

void main() {
  const query = (
    themeId: 'culture',
    themeLabel: 'Culture',
    brief: 'expos',
    anglesKey: 'Musées|Expositions',
    keywordsKey: 'macba|vernissage',
  );

  test('expose les sources renvoyées par le repo et split les clés', () async {
    final repo = _FakeRepo(const [
      VeilleSourceSuggestionDto(
        name: 'MACBA',
        url: 'https://www.macba.cat',
        why: 'Musée officiel',
        relevanceScore: 1,
      ),
    ]);
    final container = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final sources = await container.read(
      veilleSourceSuggestionsProvider(query).future,
    );
    expect(sources.single.name, 'MACBA');
    expect(repo.capturedAngles, ['Musées', 'Expositions']);
    expect(repo.capturedKeywords, ['macba', 'vernissage']);
  });

  test('repo fallback [] : provider renvoie une liste vide', () async {
    final container = ProviderContainer(
      overrides: [
        veilleRepositoryProvider.overrideWithValue(_FakeRepo(const [])),
      ],
    );
    addTearDown(container.dispose);

    final sources = await container.read(
      veilleSourceSuggestionsProvider(query).future,
    );
    expect(sources, isEmpty);
  });

  test('erreur API repo : provider expose un AsyncError', () async {
    final container = ProviderContainer(
      overrides: [
        veilleRepositoryProvider.overrideWithValue(
          _FakeRepo(
            const [],
            error: const VeilleApiException(
              'requête invalide',
              statusCode: 422,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await expectLater(
      container.read(veilleSourceSuggestionsProvider(query).future),
      throwsA(isA<VeilleApiException>()),
    );
  });
}
