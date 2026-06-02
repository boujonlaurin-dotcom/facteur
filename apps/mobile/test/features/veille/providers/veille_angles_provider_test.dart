import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_angles_provider.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';

/// Repo factice : renvoie une liste d'angles fixe (ou `[]` pour simuler un LLM
/// KO, ce que fait le vrai repo via try/catch). `suggestAngles` est la seule
/// méthode exercée ici.
class _FakeRepo implements VeilleRepository {
  final List<VeilleAngleSuggestionDto> angles;
  _FakeRepo(this.angles);

  @override
  Future<List<VeilleAngleSuggestionDto>> suggestAngles({
    required String themeId,
    required String themeLabel,
    String brief = '',
  }) async =>
      angles;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

void main() {
  const query = (themeId: 'tech', themeLabel: 'Technologie', brief: '');

  test('expose les angles renvoyés par le repo', () async {
    final repo = _FakeRepo(const [
      VeilleAngleSuggestionDto(title: 'IA', keywords: ['llm']),
    ]);
    final container = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);

    final angles = await container.read(veilleAnglesProvider(query).future);
    expect(angles.single.title, 'IA');
  });

  test(
      'LLM KO (repo → []) : provider renvoie une liste vide (fallback presets)',
      () async {
    final container = ProviderContainer(
      overrides: [
        veilleRepositoryProvider.overrideWithValue(_FakeRepo(const []))
      ],
    );
    addTearDown(container.dispose);

    final angles = await container.read(veilleAnglesProvider(query).future);
    expect(angles, isEmpty);
  });
}
