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
  String? name,
}) {
  return Source(
    id: id,
    name: name ?? 'Source $id',
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

  // ─────────────────────────────────────────────────────────────────────────
  // Signal pôle *généralisé* (v7) : un vote au swipe repondère TOUTES les
  // sources du même pôle, pas seulement la carte swipée.
  // ─────────────────────────────────────────────────────────────────────────
  group('SourceRecommender — signal pôle généralisé', () {
    Map<String, RecommendedSource> byId(SourceRecommendation r) => {
          for (final rec in [
            ...r.matched,
            ...r.perspective,
            ...r.gems,
            ...r.catalog,
          ])
            rec.source.id: rec
        };

    test('un like booste une source non swipée du même pôle (deep)', () {
      final sources = [
        _src('deep-liked', theme: 'tech', tier: 'deep'),
        // même pôle (deep) mais hors-thème et non swipée → doit être boostée.
        _src('deep-other',
            theme: 'sport', tier: 'deep', reliability: 'unknown'),
        // autre pôle (mainstream) hors-thème → aucun boost.
        _src('main-other',
            theme: 'sport', tier: 'mainstream', reliability: 'unknown'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['deep-liked'],
      );

      final m = byId(reco);
      expect(m['deep-other']!.score, greaterThan(0),
          reason: 'le pôle deep liké booste les autres sources deep');
      expect(m['deep-other']!.score, greaterThan(m['main-other']!.score),
          reason: 'le boost vise le pôle, pas les autres pôles');
    });

    test('un rejet pénalise une autre source du même pôle (deep)', () {
      final sources = [
        _src('deep-bad', theme: 'tech', tier: 'deep'),
        _src('deep-other', theme: 'tech', tier: 'deep'),
        _src('main-other', theme: 'tech', tier: 'mainstream'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeDisliked: const ['deep-bad'],
      );

      final m = byId(reco);
      expect(m['deep-other']!.score, lessThan(m['main-other']!.score),
          reason: 'le rejet du pôle deep pénalise les autres sources deep');
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Tag « Similaire à » (v7 / PR2) : raccroche une reco à une source likée au
  // swipe partageant thème + (tier ou biais).
  // ─────────────────────────────────────────────────────────────────────────
  group('SourceRecommender — tag « Similaire à »', () {
    RecommendationTag? similarTagOf(SourceRecommendation r, String id) {
      for (final rec in [...r.matched, ...r.perspective, ...r.gems]) {
        if (rec.source.id == id) {
          for (final t in rec.tags) {
            if (t.type == RecommendationTagType.similar) return t;
          }
        }
      }
      return null;
    }

    test('une reco partageant thème + tier avec une likée reçoit le tag', () {
      final sources = [
        _src('anchor',
            name: 'Le Monde', theme: 'tech', tier: 'deep', followers: 999),
        // même thème + même tier (deep) → similaire à l'ancre likée.
        _src('reco', theme: 'tech', tier: 'deep'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['anchor'],
      );

      final tag = similarTagOf(reco, 'reco');
      expect(tag, isNotNull,
          reason: 'thème + tier partagés avec une source likée');
      expect(tag!.label, contains('Le Monde'));
    });

    test('une reco partageant thème + biais avec une likée reçoit le tag', () {
      final sources = [
        _src('anchor',
            name: 'Libération',
            theme: 'tech',
            tier: 'mainstream',
            bias: 'left',
            followers: 999),
        // tier différent mais même biais (left) + même thème → similaire.
        _src('reco', theme: 'tech', tier: 'deep', bias: 'left'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['anchor'],
      );

      final tag = similarTagOf(reco, 'reco');
      expect(tag, isNotNull);
      expect(tag!.label, contains('Libération'));
    });

    test('sans like : aucun tag similar', () {
      final sources = [
        _src('a', theme: 'tech', tier: 'deep'),
        _src('b', theme: 'tech', tier: 'deep'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      expect(similarTagOf(reco, 'a'), isNull);
      expect(similarTagOf(reco, 'b'), isNull);
    });

    test('thème commun mais ni tier ni biais partagé : pas de tag', () {
      final sources = [
        _src('anchor',
            name: 'Mediapart',
            theme: 'tech',
            tier: 'deep',
            bias: 'left',
            followers: 999),
        // même thème mais tier ET biais différents → pas similaire.
        _src('reco', theme: 'tech', tier: 'mainstream', bias: 'right'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['anchor'],
      );

      expect(similarTagOf(reco, 'reco'), isNull);
    });
  });

  group('SourceRecommender.buildSpanningSet', () {
    test('étale ~8-10 cartes (N par pôle) sur plusieurs pôles', () {
      // 2 candidats « purs » par pôle → set bien rempli (round-robin perPole=2).
      final sources = [
        _src('deep-1', theme: 'tech', tier: 'deep', reliability: 'unknown',
            followers: 50),
        _src('deep-2', theme: 'tech', tier: 'deep', reliability: 'unknown',
            followers: 40),
        _src('indie-1', theme: 'tech', independence: 0.9, bias: 'alternative'),
        _src('indie-2', theme: 'tech', independence: 0.8, bias: 'specialized'),
        _src('est-1', theme: 'tech', independence: 0.2, reliability: 'high'),
        _src('est-2', theme: 'tech', independence: 0.3, reliability: 'high'),
        _src('main-1', theme: 'tech', tier: 'mainstream',
            reliability: 'unknown', followers: 100),
        _src('main-2', theme: 'tech', tier: 'mainstream',
            reliability: 'unknown', followers: 90),
        _src('left-1', theme: 'tech', bias: 'left', reliability: 'unknown'),
        _src('right-1', theme: 'tech', bias: 'right', reliability: 'unknown'),
      ];

      final set = SourceRecommender.buildSpanningSet(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      expect(set.length, lessThanOrEqualTo(10));
      expect(set.length, greaterThanOrEqualTo(8));
      final ids = set.map((s) => s.source.id).toList();
      expect(ids.toSet().length, ids.length, reason: 'pas de doublon');
      final poles = set.map((s) => s.pole).toSet();
      expect(poles.length, greaterThanOrEqualTo(4),
          reason: 'plusieurs pôles couverts');
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
