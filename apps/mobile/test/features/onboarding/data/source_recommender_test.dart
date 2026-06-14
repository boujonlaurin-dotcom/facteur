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

/// Builder plus complet pour exercer les axes "profondeur" (v6).
Source _src(
  String id, {
  String reliability = 'high',
  String? theme,
  String tier = 'mainstream',
  double? independence,
  String bias = 'unknown',
  int followers = 0,
}) {
  return Source(
    id: id,
    name: 'Source $id',
    type: SourceType.article,
    isCurated: true,
    reliabilityScore: reliability,
    theme: theme,
    sourceTier: tier,
    scoreIndependence: independence,
    biasStance: bias,
    followerCount: followers,
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

  group('SourceRecommender — axes profondeur (v6)', () {
    test('swipeLiked remonte une source hors-thème en tête des matched', () {
      final sources = [
        _src('tech-1', theme: 'tech'), // 3 + 1 = 4
        _src('tech-2', theme: 'tech'), // 4
        _src('off', theme: 'sport', reliability: 'unknown'), // 0 → +5 like = 5
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['off'],
      );

      expect(reco.matched.first.source.id, 'off',
          reason: 'Le like révélé doit primer sur le match thématique');
    });

    test('swipeDisliked exclut une source des matched malgré un match thème',
        () {
      final sources = [
        _src('tech-1', theme: 'tech'),
        _src('tech-2', theme: 'tech'),
        _src('tech-bad', theme: 'tech'), // 4 - 4 = 0 → exclu des matched
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeDisliked: const ['tech-bad'],
      );

      final matchedIds = reco.matched.map((r) => r.source.id);
      expect(matchedIds, containsAll(<String>['tech-1', 'tech-2']));
      expect(matchedIds, isNot(contains('tech-bad')),
          reason: 'Le rejet révélé doit retirer la source des suggestions');
    });

    test('depthPref oriente le tier privilégié', () {
      final sources = [
        _src('deep-1', theme: 'tech', tier: 'deep'),
        _src('main-1', theme: 'tech', tier: 'mainstream'),
      ];

      final detailed = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        depthPref: 'detailed',
      );
      expect(detailed.matched.first.source.id, 'deep-1');

      final direct = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        depthPref: 'direct',
      );
      expect(direct.matched.first.source.id, 'main-1');
    });

    test('independencePref=independent booste la forte indépendance', () {
      final sources = [
        _src('indie',
            theme: 'tech', independence: 0.9, reliability: 'unknown'),
        _src('inst', theme: 'tech', independence: 0.2), // reliability high
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        independencePref: 'independent',
      );

      expect(reco.matched.first.source.id, 'indie');
    });
  });

  group('SourceRecommender.buildSpanningSet', () {
    test('étale les cartes sur des pôles distincts', () {
      final sources = [
        _src('deep', theme: 'tech', tier: 'deep', followers: 10),
        _src('main', theme: 'tech', tier: 'mainstream', followers: 100),
        _src('indie', theme: 'tech', independence: 0.9, bias: 'alternative'),
        _src('inst', theme: 'tech', independence: 0.2, reliability: 'high'),
        _src('left', theme: 'tech', bias: 'left'),
        _src('right', theme: 'tech', bias: 'right'),
      ];

      final set = SourceRecommender.buildSpanningSet(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      expect(set.length, lessThanOrEqualTo(5));
      expect(set.length, greaterThanOrEqualTo(3));
      final ids = set.map((s) => s.source.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'pas de doublon');
      final poles = set.map((s) => s.pole).toSet();
      expect(poles.length, set.length, reason: 'un pôle distinct par carte');
    });

    test('renvoie une liste vide sans source curée', () {
      expect(
        SourceRecommender.buildSpanningSet(
          selectedThemes: const [],
          selectedSubtopics: const [],
          allSources: const [],
        ),
        isEmpty,
      );
    });

    test('thèmes pauvres : complète depuis le catalogue large', () {
      final sources = [
        _src('a', theme: 'sport', tier: 'deep', followers: 50),
        _src('b', theme: 'sport', tier: 'mainstream', followers: 40),
        _src('c', theme: 'sport', independence: 0.9),
      ];

      // L'utilisateur a choisi 'tech' (0 match) → fallback catalogue large.
      final set = SourceRecommender.buildSpanningSet(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      expect(set, isNotEmpty);
    });
  });
}
