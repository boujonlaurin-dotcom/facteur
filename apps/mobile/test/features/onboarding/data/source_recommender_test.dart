import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/onboarding/data/source_recommender.dart';
import 'package:facteur/features/onboarding/onboarding_strings.dart';
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
  int articles30d = 0,
  SourceType type = SourceType.article,
  String? name,
}) {
  return Source(
    id: id,
    name: name ?? 'Source $id',
    type: type,
    isCurated: true,
    reliabilityScore: reliability,
    theme: theme,
    sourceTier: tier,
    scoreIndependence: independence,
    biasStance: bias,
    followerCount: followers,
    articles30d: articles30d,
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
        reason:
            'Le fallback fiabilité doit garantir un plancher de suggestions',
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

      expect(
        reco.matched.first.source.id,
        'off',
        reason: 'Le like révélé doit primer sur le match thématique',
      );
    });

    test(
      'swipeDisliked exclut une source des matched malgré un match thème',
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
        expect(
          matchedIds,
          isNot(contains('tech-bad')),
          reason: 'Le rejet révélé doit retirer la source des suggestions',
        );
      },
    );

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
        _src('indie', theme: 'tech', independence: 0.9, reliability: 'unknown'),
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
        rec.source.id: rec,
    };

    test('un like booste une source non swipée du même pôle (deep)', () {
      final sources = [
        _src('deep-liked', theme: 'tech', tier: 'deep'),
        // même pôle (deep) mais hors-thème et non swipée → doit être boostée.
        _src(
          'deep-other',
          theme: 'sport',
          tier: 'deep',
          reliability: 'unknown',
        ),
        // autre pôle (mainstream) hors-thème → aucun boost.
        _src(
          'main-other',
          theme: 'sport',
          tier: 'mainstream',
          reliability: 'unknown',
        ),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['deep-liked'],
      );

      final m = byId(reco);
      expect(
        m['deep-other']!.score,
        greaterThan(0),
        reason: 'le pôle deep liké booste les autres sources deep',
      );
      expect(
        m['deep-other']!.score,
        greaterThan(m['main-other']!.score),
        reason: 'le boost vise le pôle, pas les autres pôles',
      );
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
      expect(
        m['deep-other']!.score,
        lessThan(m['main-other']!.score),
        reason: 'le rejet du pôle deep pénalise les autres sources deep',
      );
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
        _src(
          'anchor',
          name: 'Le Monde',
          theme: 'tech',
          tier: 'deep',
          followers: 999,
        ),
        // même thème + même tier (deep) → similaire à l'ancre likée.
        _src('reco', theme: 'tech', tier: 'deep'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const [],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['anchor'],
      );

      final tag = similarTagOf(reco, 'reco');
      expect(
        tag,
        isNotNull,
        reason: 'thème + tier partagés avec une source likée',
      );
      expect(tag!.label, contains('Le Monde'));
    });

    test('une reco partageant thème + biais avec une likée reçoit le tag', () {
      final sources = [
        _src(
          'anchor',
          name: 'Libération',
          theme: 'tech',
          tier: 'mainstream',
          bias: 'left',
          followers: 999,
        ),
        // tier différent mais même biais (left) + même thème → similaire.
        _src('reco', theme: 'tech', tier: 'deep', bias: 'left'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const [],
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
        _src(
          'anchor',
          name: 'Mediapart',
          theme: 'tech',
          tier: 'deep',
          bias: 'left',
          followers: 999,
        ),
        // même thème mais tier ET biais différents → pas similaire.
        _src('reco', theme: 'tech', tier: 'mainstream', bias: 'right'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const [],
        selectedSubtopics: const [],
        allSources: sources,
        swipeLiked: const ['anchor'],
      );

      expect(similarTagOf(reco, 'reco'), isNull);
    });

    test(
      'limite le tag similaire à 2 occurrences et le masque si tag précis',
      () {
        final sources = [
          _src(
            'anchor',
            name: 'Sismique',
            theme: 'tech',
            tier: 'deep',
            followers: 999,
          ),
          for (var i = 0; i < 4; i++)
            _src('similar-$i', theme: 'tech', tier: 'deep'),
          _src('precise', theme: 'tech', tier: 'deep'),
        ];

        final recoNoPrecise = SourceRecommender.recommend(
          selectedThemes: const [],
          selectedSubtopics: const [],
          allSources: sources,
          swipeLiked: const ['anchor'],
        );

        final allVisible = [
          ...recoNoPrecise.specialists,
          ...recoNoPrecise.matched,
          ...recoNoPrecise.perspective,
          ...recoNoPrecise.gems,
        ];
        final similarToSismique = allVisible
            .expand((r) => r.tags)
            .where((t) => t.label == 'Similaire à Sismique')
            .length;

        expect(similarToSismique, 2);

        final recoPrecise = SourceRecommender.recommend(
          selectedThemes: const ['tech'],
          selectedSubtopics: const [],
          allSources: sources,
          swipeLiked: const ['anchor'],
        );
        expect(
          similarTagOf(recoPrecise, 'precise'),
          isNull,
          reason: 'le tag thème Tech est plus précis que le fallback similaire',
        );
      },
    );
  });

  group('SourceRecommender.buildSpanningSet', () {
    test('étale ~8-10 cartes (N par pôle) sur plusieurs pôles', () {
      // 2 candidats « purs » par pôle → set bien rempli (round-robin perPole=2).
      final sources = [
        _src(
          'deep-1',
          theme: 'tech',
          tier: 'deep',
          reliability: 'unknown',
          followers: 50,
        ),
        _src(
          'deep-2',
          theme: 'tech',
          tier: 'deep',
          reliability: 'unknown',
          followers: 40,
        ),
        _src('indie-1', theme: 'tech', independence: 0.9, bias: 'alternative'),
        _src('indie-2', theme: 'tech', independence: 0.8, bias: 'specialized'),
        _src('est-1', theme: 'tech', independence: 0.2, reliability: 'high'),
        _src('est-2', theme: 'tech', independence: 0.3, reliability: 'high'),
        _src(
          'main-1',
          theme: 'tech',
          tier: 'mainstream',
          reliability: 'unknown',
          followers: 100,
        ),
        _src(
          'main-2',
          theme: 'tech',
          tier: 'mainstream',
          reliability: 'unknown',
          followers: 90,
        ),
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
      expect(
        poles.length,
        greaterThanOrEqualTo(4),
        reason: 'plusieurs pôles couverts',
      );
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

    test('tiebreaker volume : à thème égal, la source productive remonte', () {
      // Deux sources mainstream identiques sauf le volume — la productive
      // (articles30d élevé) doit être préférée, même avec moins de followers.
      final sources = [
        _src(
          'quiet',
          theme: 'tech',
          tier: 'mainstream',
          reliability: 'unknown',
          followers: 1000,
          articles30d: 0,
        ),
        _src(
          'active',
          theme: 'tech',
          tier: 'mainstream',
          reliability: 'unknown',
          followers: 10,
          articles30d: 200,
        ),
      ];

      final set = SourceRecommender.buildSpanningSet(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
        maxCards: 1,
        perPole: 1,
      );

      expect(
        set.first.source.id,
        'active',
        reason: 'volume prime sur followers à match égal',
      );
    });
  });

  group('SourceRecommender — biais « sources productives »', () {
    test('à thème égal, une source productive est classée au-dessus', () {
      final sources = [
        _src('active', theme: 'tech', articles30d: 120), // +2 volume
        _src('quiet', theme: 'tech', articles30d: 0), // no-op
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      final ids = reco.matched.map((r) => r.source.id).toList();
      expect(
        ids.indexOf('active'),
        lessThan(ids.indexOf('quiet')),
        reason: 'le bonus volume départage à match thématique égal',
      );
    });

    test('articles30d absent (0) : aucun effet (rétro-compatible)', () {
      // Sans signal volume, le classement reste piloté par les autres axes :
      // ici 'b' gagne uniquement par sa fiabilité, pas par un volume fantôme.
      final sources = [
        _src('a', theme: 'tech', reliability: 'unknown', articles30d: 0),
        _src('b', theme: 'tech', reliability: 'high', articles30d: 0),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      final ids = reco.matched.map((r) => r.source.id).toList();
      expect(ids.indexOf('b'), lessThan(ids.indexOf('a')));
    });
  });

  // ─────────────────────────────────────────────────────────────────────────
  // Badge « spécialiste » + garantie de couverture (Epic 12 / re-tag sources).
  // ─────────────────────────────────────────────────────────────────────────
  group('SourceRecommender — spécialiste & garantie de couverture', () {
    Source spec(
      String id, {
      required List<String> topics,
      String reliability = 'high',
      String? theme,
    }) => Source(
      id: id,
      name: 'Source $id',
      type: SourceType.article,
      isCurated: true,
      reliabilityScore: reliability,
      theme: theme,
      granularTopics: topics,
    );

    bool hasSpecialistTag(RecommendedSource r) =>
        r.tags.any((t) => t.type == RecommendationTagType.specialist);

    test('spécialité dominante ∈ sujets → badge « Spécialisé en X »', () {
      final sources = [
        spec('ai', topics: ['ai', 'tech'], theme: 'tech'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const ['ai'],
        allSources: sources,
      );

      final card = reco.matched.firstWhere((r) => r.source.id == 'ai');
      expect(hasSpecialistTag(card), isTrue);
      expect(
        card.tags
            .firstWhere((t) => t.type == RecommendationTagType.specialist)
            .label,
        'Spécialisé en Intelligence artificielle',
      );
    });

    test('subtopic non dominant → pas de badge spécialiste sur cette source', () {
      // 'ai' n'est PAS la spécialité dominante (tech l'est) → la carte garde un
      // tag thème « IA » mais aucun badge spécialiste.
      final sources = [
        spec('s', topics: ['tech', 'ai'], theme: 'tech'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const ['ai'],
        allSources: sources,
      );

      final card = reco.matched.firstWhere((r) => r.source.id == 's');
      expect(hasSpecialistTag(card), isFalse);
    });

    test(
      'garantie : un spécialiste hors-matched est remonté dans specialists',
      () {
        // 15 sources tech (score 4) saturent matched ; le spécialiste factcheck
        // (score 2) en serait exclu → la garantie de couverture le rapatrie.
        final sources = [
          for (var i = 0; i < 15; i++)
            spec('tech-$i', topics: const [], theme: 'tech'),
          spec('fc', topics: const ['factcheck'], reliability: 'unknown'),
        ];

        final reco = SourceRecommender.recommend(
          selectedThemes: const ['tech'],
          selectedSubtopics: const ['factcheck'],
          allSources: sources,
        );

        expect(
          reco.matched.any((r) => r.source.id == 'fc'),
          isFalse,
          reason: 'le spécialiste de faible score ne rentre pas dans matched',
        );
        final fc = reco.specialists.firstWhere((r) => r.source.id == 'fc');
        expect(hasSpecialistTag(fc), isTrue);
        expect(
          fc.tags
              .firstWhere((t) => t.type == RecommendationTagType.specialist)
              .label,
          'Spécialisé en Fact-checking',
        );
        // Pré-coché pour l'effet « wow ».
        expect(reco.preselectedIds, contains('fc'));
      },
    );

    test('spécialiste déjà dominant dans matched → pas de doublon', () {
      final sources = [
        spec('ai', topics: const ['ai'], theme: 'tech'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const ['ai'],
        allSources: sources,
      );

      expect(reco.matched.any((r) => r.source.id == 'ai'), isTrue);
      expect(hasSpecialistTag(reco.matched.first), isTrue);
      // Déjà couvert par matched → aucun gap-filler.
      expect(reco.specialists, isEmpty);
    });

    test('chaque subtopic obtient une carte spécialiste distincte', () {
      // Deux sujets « pauvres » non couverts par matched ; deux spécialistes
      // distincts disponibles → une carte chacun.
      final sources = [
        for (var i = 0; i < 15; i++)
          spec('tech-$i', topics: const [], theme: 'tech'),
        spec('fc', topics: const ['factcheck'], reliability: 'unknown'),
        spec('rel', topics: const ['relationships'], reliability: 'unknown'),
      ];

      final reco = SourceRecommender.recommend(
        selectedThemes: const ['tech'],
        selectedSubtopics: const ['factcheck', 'relationships'],
        allSources: sources,
      );

      final specialistIds = reco.specialists.map((r) => r.source.id).toSet();
      expect(specialistIds, containsAll(<String>['fc', 'rel']));
    });
  });

  group('SourceRecommender.buildSpanningGroups — groupes contigus', () {
    // Un représentant net par pôle (mainstream / deep / indépendant / établi).
    List<Source> spanningDeck() => [
          _src('main', tier: 'mainstream', articles30d: 50),
          _src('deep', tier: 'deep', articles30d: 50),
          _src('indie', independence: 0.9, bias: 'alternative'),
          _src('estab', reliability: 'high', independence: 0.2),
        ];

    int poleIndex(List<SwipeGroup> groups, SwipeAxisPole pole) =>
        groups.indexWhere((g) => g.pole == pole);

    test('regroupe les cartes en blocs contigus par pôle (pas de doublon)', () {
      final groups = SourceRecommender.buildSpanningGroups(
        selectedThemes: const [],
        selectedSubtopics: const [],
        allSources: spanningDeck(),
      );
      // Un groupe par pôle présent, chaque pôle apparaît une seule fois.
      final poles = groups.map((g) => g.pole).toList();
      expect(poles.toSet().length, poles.length);
      // Mêmes cartes que le spanning set sous-jacent (calibration inchangée).
      final flat = groups.expand((g) => g.cards).map((c) => c.source.id).toSet();
      expect(flat, {'main', 'deep', 'indie', 'estab'});
    });

    test('independencePref « independent » mène avec indépendant/fond', () {
      final groups = SourceRecommender.buildSpanningGroups(
        selectedThemes: const [],
        selectedSubtopics: const [],
        allSources: spanningDeck(),
        independencePref: 'independent',
      );
      expect(
        poleIndex(groups, SwipeAxisPole.independent),
        lessThan(poleIndex(groups, SwipeAxisPole.mainstream)),
      );
      expect(
        poleIndex(groups, SwipeAxisPole.deep),
        lessThan(poleIndex(groups, SwipeAxisPole.established)),
      );
    });

    test('independencePref « established » mène avec établis/grands médias', () {
      final groups = SourceRecommender.buildSpanningGroups(
        selectedThemes: const [],
        selectedSubtopics: const [],
        allSources: spanningDeck(),
        independencePref: 'established',
      );
      expect(
        poleIndex(groups, SwipeAxisPole.established),
        lessThan(poleIndex(groups, SwipeAxisPole.independent)),
      );
      expect(
        poleIndex(groups, SwipeAxisPole.mainstream),
        lessThan(poleIndex(groups, SwipeAxisPole.independent)),
      );
    });

    test('depthPref « detailed » remonte le groupe « fond » en tête', () {
      final groups = SourceRecommender.buildSpanningGroups(
        selectedThemes: const [],
        selectedSubtopics: const [],
        allSources: spanningDeck(),
        depthPref: 'detailed',
      );
      expect(groups.first.pole, SwipeAxisPole.deep);
    });

    test('libellé thématique quand le groupe est cohérent sur un thème pref',
        () {
      final sources = [
        _src('d1', tier: 'deep', theme: 'tech'),
        _src('d2', tier: 'deep', theme: 'tech'),
        _src('m1', tier: 'mainstream', theme: 'society'),
      ];
      final groups = SourceRecommender.buildSpanningGroups(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: sources,
      );

      final deepGroup =
          groups.firstWhere((g) => g.pole == SwipeAxisPole.deep);
      expect(
        deepGroup.label,
        OnboardingStrings.swipeGroupThemedDeep
            .replaceFirst('%s', 'Tech & Innovation'),
      );

      // Le groupe mainstream (thème society hors prefs) garde un libellé de pôle.
      final mainGroup =
          groups.firstWhere((g) => g.pole == SwipeAxisPole.mainstream);
      expect(mainGroup.label, OnboardingStrings.swipeGroupMainstream);
    });

    test('catalogue minimal : dégrade en un groupe à libellé de pôle', () {
      final groups = SourceRecommender.buildSpanningGroups(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: [_src('only', tier: 'mainstream')],
      );
      expect(groups, isNotEmpty);
      expect(groups.expand((g) => g.cards).length, 1);
      expect(groups.first.label, OnboardingStrings.swipeGroupMainstream);
    });

    test('aucune source → aucun groupe', () {
      final groups = SourceRecommender.buildSpanningGroups(
        selectedThemes: const ['tech'],
        selectedSubtopics: const [],
        allSources: const [],
      );
      expect(groups, isEmpty);
    });
  });
}
