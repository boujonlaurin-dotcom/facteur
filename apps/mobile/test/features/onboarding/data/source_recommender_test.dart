import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/onboarding/data/source_recommender.dart';
import 'package:facteur/features/sources/models/source_model.dart';

Source _curated(String id, {String reliability = 'high', String? theme}) {
  return Source(
    id: id,
    name: 'Source $id',
    type: SourceType.article,
    isCurated: true,
    reliabilityScore: reliability,
    theme: theme,
  );
}

void main() {
  group('SourceRecommender.recommend — thèmes vides (bouton Passer)', () {
    test('renvoie ≥ 5 sources matched via le bonus fiabilité', () {
      // L'utilisateur a sauté la question thèmes → selectedThemes vide. Les
      // sources fiables (reliabilityScore == high) marquent +1 et garnissent
      // donc la liste matched même sans correspondance thématique.
      final sources = [
        for (var i = 0; i < 8; i++) _curated('high-$i'),
        // quelques sources non fiables : ne doivent pas être nécessaires.
        _curated('low-1', reliability: 'unknown'),
        _curated('low-2', reliability: 'unknown'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const [],
        selectedSubtopics: const [],
        allSources: sources,
      );

      expect(
        reco.matched.length,
        greaterThanOrEqualTo(5),
        reason: 'Le fallback fiabilité doit garantir un plancher de suggestions',
      );
    });

    test('thèmes renseignés : les matchs thématiques priment', () {
      final sources = [
        _curated('tech-1', theme: 'tech'),
        _curated('tech-2', theme: 'tech'),
        _curated('sport-1', theme: 'sport'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      final matchedIds = reco.matched.map((r) => r.source.id).toList();
      expect(matchedIds, containsAll(<String>['tech-1', 'tech-2']));
    });
  });
}
