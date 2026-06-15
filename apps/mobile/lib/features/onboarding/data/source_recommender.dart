import 'package:flutter/foundation.dart';

import '../../../config/topic_labels.dart';
import '../../sources/models/source_model.dart';

/// Category of a recommended source.
enum SourceCategory {
  matched,
  perspective,
  gem,
  catalog,
}

/// Type of recommendation tag displayed on a source card.
enum RecommendationTagType {
  /// Theme or subtopic match (e.g., "Tech", "IA")
  topic,

  /// Deep analysis source — shown when user selected "noise" objective
  antiBruit,

  /// Reliable source — shown when user selected "bias" objective
  fiable,

  /// Low-anxiety theme — shown when user selected "anxiety" objective
  serein,

  /// Raccroche la reco à une source aimée au swipe ("Similaire à {nom}")
  similar,
}

/// A visual tag badge on a recommendation card.
class RecommendationTag {
  final String label;
  final RecommendationTagType type;

  const RecommendationTag({required this.label, required this.type});
}

/// A source with its recommendation category and tags.
class RecommendedSource {
  final Source source;
  final SourceCategory category;
  final List<RecommendationTag> tags;
  final String reason;
  final int score;

  const RecommendedSource({
    required this.source,
    required this.category,
    this.tags = const [],
    this.reason = '',
    this.score = 0,
  });
}

/// Result of the recommendation algorithm.
class SourceRecommendation {
  final List<RecommendedSource> matched;
  final List<RecommendedSource> perspective;
  final List<RecommendedSource> gems;
  final List<RecommendedSource> catalog;

  /// IDs that should be pre-selected.
  Set<String> get preselectedIds => {
        ...matched.map((r) => r.source.id),
        ...gems.map((r) => r.source.id),
      };

  const SourceRecommendation({
    required this.matched,
    required this.perspective,
    required this.gems,
    required this.catalog,
  });
}

/// Pôle d'axe sondé par une carte du swipe désambiguateur. Chaque carte
/// incarne un pôle distinct pour révéler les préférences "profondes".
enum SwipeAxisPole { deep, mainstream, independent, established, perspective }

/// Une source retenue pour le swipe, avec le pôle d'axe qu'elle sonde.
class SpanningSource {
  final Source source;
  final SwipeAxisPole pole;
  const SpanningSource({required this.source, required this.pole});
}

/// Computes personalized source recommendations based on user's onboarding choices.
///
/// Replaces the static ThemeToSourcesMapping with dynamic scoring using
/// source.theme, source.granularTopics, source.secondaryThemes, and source.sourceTier.
class SourceRecommender {
  static const int _maxMatched = 15;
  static const int _minMatched = 10;
  static const int _maxPerspective = 5;
  static const int _maxGems = 5;

  /// Themes considered low-anxiety (for "anxiety" objective tag).
  static const _sereinThemes = {'tech', 'science', 'culture', 'sport'};

  /// Compute recommendations from user choices and available sources.
  ///
  /// Axes "profondeur" ré-aiguillés (onboarding v6) — optionnels, sans défaut
  /// imposé : un appel sans ces paramètres garde le comportement historique.
  /// - [depthPref] : `direct` (actu factuelle) | `detailed` (analyse de fond),
  ///   ré-aiguillé de `approach` ;
  /// - [independencePref] : `established` (références) | `independent`
  ///   (pure-players) ;
  /// - [swipeLiked]/[swipeDisliked] : IDs triés au swipe désambiguateur —
  ///   signal *révélé* qui repondère le scoring de deux façons : (1) boost/malus
  ///   fort sur la source swipée elle-même (`+5/-4`) ; (2) signal *généralisé*
  ///   par pôle d'axe — les votes sont agrégés par pôle (fond / actu directe /
  ///   indépendant / référence) et appliqués à **toutes** les sources du même
  ///   pôle (pas seulement les 5 swipées), capé pour ne pas écraser le déclaratif.
  static SourceRecommendation recommend({
    required List<String> selectedThemes,
    required List<String> selectedSubtopics,
    required List<Source> allSources,
    List<String> objectives = const [],
    String? depthPref,
    String? independencePref,
    List<String> swipeLiked = const [],
    List<String> swipeDisliked = const [],
  }) {
    final curated = allSources.where((s) => s.isCurated).toList();

    final hasNoise = objectives.contains('noise');
    final hasBias = objectives.contains('bias');
    final hasAnxiety = objectives.contains('anxiety');
    final likedSet = swipeLiked.toSet();
    final dislikedSet = swipeDisliked.toSet();

    // Signal *révélé* agrégé par pôle d'axe : classe chaque source swipée dans
    // son/ses pôle(s) intrinsèque(s) et somme +1 (liké) / -1 (rejeté). Ce net
    // par pôle est ensuite appliqué à toutes les sources du même pôle.
    final poleVotes = _aggregatePoleVotes(curated, likedSet, dislikedSet);

    // Score all sources
    final scored = <String, int>{};
    final tagResults = <String, _ScoreResult>{};

    for (final source in curated) {
      final result = _scoreSource(
        source: source,
        themes: selectedThemes,
        subtopics: selectedSubtopics,
        hasNoise: hasNoise,
        hasBias: hasBias,
        hasAnxiety: hasAnxiety,
        depthPref: depthPref,
        independencePref: independencePref,
        swipeLiked: likedSet,
        swipeDisliked: dislikedSet,
        poleVotes: poleVotes,
      );
      scored[source.id] = result.score;
      tagResults[source.id] = result;
    }

    // Sort by score descending
    final sortedByScore = List.of(curated)
      ..sort((a, b) => (scored[b.id] ?? 0).compareTo(scored[a.id] ?? 0));

    // Partition into categories
    final matchedSources = <RecommendedSource>[];
    final usedIds = <String>{};

    // 1. Matched: top scoring sources with score > 0
    for (final source in sortedByScore) {
      if (matchedSources.length >= _maxMatched) break;
      if ((scored[source.id] ?? 0) <= 0) {
        if (matchedSources.length >= _minMatched) break;
        continue;
      }
      final result = tagResults[source.id]!;
      matchedSources.add(RecommendedSource(
        source: source,
        category: SourceCategory.matched,
        tags: result.tags,
        reason: result.reason,
        score: scored[source.id] ?? 0,
      ));
      usedIds.add(source.id);
    }

    // 2. Perspective: opposite bias from majority
    final perspectiveSources = _computePerspective(
      matched: matchedSources,
      allCurated: curated,
      usedIds: usedIds,
    );
    for (final r in perspectiveSources) {
      usedIds.add(r.source.id);
    }

    // 3. Gems: deep tier sources not already used
    final gemSources = _computeGems(
      allCurated: curated,
      usedIds: usedIds,
      scored: scored,
    );
    for (final r in gemSources) {
      usedIds.add(r.source.id);
    }

    // 4. Catalog: everything else, alphabetical
    final catalogSources = curated
        .where((s) => !usedIds.contains(s.id))
        .toList()
      ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

    final catalogRecommended = catalogSources
        .map((s) => RecommendedSource(
              source: s,
              category: SourceCategory.catalog,
              reason: '',
            ))
        .toList();

    // Tag « Similaire à {nom} » : raccroche chaque reco (matched / perspective /
    // gems) à la meilleure source aimée AU SWIPE partageant thème + (tier ou
    // biais). Pas le catalogue (déjà replié), pas les sources déjà suivies.
    final likedSources =
        curated.where((s) => likedSet.contains(s.id)).toList();

    List<RecommendedSource> withSimilarTag(List<RecommendedSource> list) {
      if (likedSources.isEmpty) return list;
      return list.map((r) {
        final tag = _similarTag(r.source, likedSources);
        if (tag == null) return r;
        return RecommendedSource(
          source: r.source,
          category: r.category,
          tags: [tag, ...r.tags],
          reason: r.reason,
          score: r.score,
        );
      }).toList();
    }

    return SourceRecommendation(
      matched: withSimilarTag(matchedSources),
      perspective: withSimilarTag(perspectiveSources),
      gems: withSimilarTag(gemSources),
      catalog: catalogRecommended,
    );
  }

  /// Cherche la meilleure source aimée au swipe « similaire » à [s] : partage un
  /// thème (principal ou secondaire) **et** (même `sourceTier` **ou** même
  /// `biasStance` connu). Départage par `followerCount` desc. Renvoie le tag
  /// `'Similaire à {nom}'` ou `null` si aucune ancre.
  static RecommendationTag? _similarTag(
    Source s,
    List<Source> likedSources,
  ) {
    Set<String> themesOf(Source x) => {
          if (x.theme != null) x.theme!,
          ...x.secondaryThemes,
        };

    final sThemes = themesOf(s);
    Source? best;
    for (final liked in likedSources) {
      if (liked.id == s.id) continue;
      if (sThemes.intersection(themesOf(liked)).isEmpty) continue;
      final sameTierOrBias = s.sourceTier == liked.sourceTier ||
          (s.biasStance != 'unknown' && s.biasStance == liked.biasStance);
      if (!sameTierOrBias) continue;
      if (best == null || liked.followerCount > best.followerCount) {
        best = liked;
      }
    }
    if (best == null) return null;
    return RecommendationTag(
      label: 'Similaire à ${best.name}',
      type: RecommendationTagType.similar,
    );
  }

  static _ScoreResult _scoreSource({
    required Source source,
    required List<String> themes,
    required List<String> subtopics,
    required bool hasNoise,
    required bool hasBias,
    required bool hasAnxiety,
    String? depthPref,
    String? independencePref,
    Set<String> swipeLiked = const {},
    Set<String> swipeDisliked = const {},
    Map<SwipeAxisPole, int> poleVotes = const {},
  }) {
    int score = 0;
    String bestReason = '';
    int bestReasonScore = 0;
    final tags = <RecommendationTag>[];

    // Theme principal match (+3)
    if (source.theme != null && themes.contains(source.theme)) {
      score += 3;
      if (3 > bestReasonScore) {
        bestReasonScore = 3;
        bestReason = getTopicLabel(source.theme!);
      }
      tags.add(RecommendationTag(
        label: getTopicLabel(source.theme!),
        type: RecommendationTagType.topic,
      ));
    }

    // Secondary themes match (+1 each)
    for (final t in source.secondaryThemes) {
      if (themes.contains(t)) {
        score += 1;
        if (bestReason.isEmpty) {
          bestReason = getTopicLabel(t);
        }
        // Only add tag for first secondary theme to avoid clutter
        if (tags.where((t) => t.type == RecommendationTagType.topic).length < 2) {
          tags.add(RecommendationTag(
            label: getTopicLabel(t),
            type: RecommendationTagType.topic,
          ));
        }
      }
    }

    // Granular topics match subtopics (+2 each)
    for (final gt in source.granularTopics) {
      if (subtopics.contains(gt)) {
        score += 2;
        if (2 > bestReasonScore) {
          bestReasonScore = 2;
          bestReason = getTopicLabel(gt);
        }
        // Add subtopic tag (prefer over theme if more specific)
        if (tags.where((t) => t.type == RecommendationTagType.topic).length < 2) {
          tags.add(RecommendationTag(
            label: getTopicLabel(gt),
            type: RecommendationTagType.topic,
          ));
        }
      }
    }

    // Reliability bonus (+1)
    if (source.reliabilityScore == 'high') {
      score += 1;
    }

    // --- Axes "profondeur" ré-aiguillés (v6) ---

    // Profondeur : aligne le tier de la source sur la préférence déclarée.
    if (depthPref == 'detailed' && source.sourceTier == 'deep') {
      score += 2;
    } else if (depthPref == 'direct' && source.sourceTier == 'mainstream') {
      score += 2;
    }

    // Indépendance : goût de sourcing (établis vs indépendants), pas un
    // jugement de fiabilité. `score_independence` est déjà sérialisé côté API.
    final independence = source.scoreIndependence;
    if (independencePref == 'independent') {
      if (independence != null && independence >= 0.7) {
        score += 3;
      } else if (independence != null && independence >= 0.5) {
        score += 1;
      }
      if (source.biasStance == 'alternative' ||
          source.biasStance == 'specialized') {
        score += 1;
      }
    } else if (independencePref == 'established') {
      // Références installées : fiables et plutôt « centrales ».
      if (source.reliabilityScore == 'high') score += 2;
      if (independence != null && independence <= 0.4) score += 1;
    }

    // Swipe désambiguateur : signal *révélé*. Un like prime sur le déclaratif
    // (boost fort + garantit la pré-sélection), un rejet pénalise nettement.
    if (swipeLiked.contains(source.id)) {
      score += 5;
    } else if (swipeDisliked.contains(source.id)) {
      score -= 4;
    }

    // Signal pôle *généralisé* : applique le net de chaque pôle de la source
    // (±2 par vote net), capé à ±4 au total pour ne pas écraser le déclaratif.
    // Rend la calibration « vraie » : aimer une source de fond booste TOUTES
    // les sources de fond, pas seulement la carte swipée.
    if (poleVotes.isNotEmpty) {
      int poleBoost = 0;
      for (final pole in _polesForSource(source)) {
        poleBoost += (poleVotes[pole] ?? 0) * 2;
      }
      score += poleBoost.clamp(-4, 4);
    }

    // --- Objective-based tags ---

    // Anti-bruit: user worried about noise → tag sources that provide depth
    // Rule: source has high reliability OR is deep-tier (= analyses profondes)
    if (hasNoise &&
        (source.sourceTier == 'deep' || source.reliabilityScore == 'high')) {
      tags.add(const RecommendationTag(
        label: 'Anti-bruit',
        type: RecommendationTagType.antiBruit,
      ));
    }

    // Source fiable: user worried about bias → tag reliable sources
    // Rule: source has high reliability score
    if (hasBias && source.reliabilityScore == 'high') {
      tags.add(const RecommendationTag(
        label: 'Source fiable',
        type: RecommendationTagType.fiable,
      ));
    }

    // Serein: user worried about anxiety → tag sources with calm themes
    // Rule: source's primary theme is in the low-anxiety set
    if (hasAnxiety &&
        source.theme != null &&
        _sereinThemes.contains(source.theme)) {
      tags.add(const RecommendationTag(
        label: 'Peu anxiogène',
        type: RecommendationTagType.serein,
      ));
    }

    final reason = bestReason.isNotEmpty
        ? 'Parce que vous suivez $bestReason'
        : '';

    return _ScoreResult(score: score, reason: reason, tags: tags);
  }

  static List<RecommendedSource> _computePerspective({
    required List<RecommendedSource> matched,
    required List<Source> allCurated,
    required Set<String> usedIds,
  }) {
    // Cible : les biais opposés à la majorité des sources matchées.
    final targetBiases = _oppositeBiases(matched.map((r) => r.source).toList());

    final candidates = allCurated
        .where((s) =>
            !usedIds.contains(s.id) && targetBiases.contains(s.biasStance))
        .toList();

    // Sort by reliability (prefer 'high')
    candidates.sort((a, b) {
      final aRel = a.reliabilityScore == 'high' ? 1 : 0;
      final bRel = b.reliabilityScore == 'high' ? 1 : 0;
      return bRel.compareTo(aRel);
    });

    return candidates
        .take(_maxPerspective)
        .map((s) => RecommendedSource(
              source: s,
              category: SourceCategory.perspective,
              reason: 'Pour voir un autre point de vue',
            ))
        .toList();
  }

  static List<RecommendedSource> _computeGems({
    required List<Source> allCurated,
    required Set<String> usedIds,
    required Map<String, int> scored,
  }) {
    // Debug: help diagnose missing Pépites section
    final allDeep = allCurated.where((s) => s.sourceTier == 'deep').toList();
    debugPrint('[SourceRecommender] _computeGems: '
        '${allCurated.length} curated sources, '
        '${allDeep.length} deep-tier sources '
        '(${allDeep.map((s) => s.name).join(", ")})');

    final candidates = allCurated
        .where((s) => !usedIds.contains(s.id) && s.sourceTier == 'deep')
        .toList();

    // Sort by relevance score (prefer ones that match user interests)
    candidates.sort((a, b) {
      final aScore = scored[a.id] ?? 0;
      final bScore = scored[b.id] ?? 0;
      return bScore.compareTo(aScore);
    });

    return candidates.take(_maxGems).map((s) {
      final desc = s.description;
      final reason = desc != null && desc.isNotEmpty
          ? (desc.length > 80 ? '${desc.substring(0, 77)}...' : desc)
          : 'Source de fond recommandée';
      return RecommendedSource(
        source: s,
        category: SourceCategory.gem,
        reason: reason,
      );
    }).toList();
  }

  /// Construit un "spanning set" pour le swipe de calibration : au plus
  /// [maxCards] sources (~8-10), **[perPole] par pôle d'axe** (round-robin),
  /// choisies parmi le curé matchant les thèmes de l'utilisateur et délibérément
  /// étalées (fond / actu directe / indépendant / référence / perspective).
  /// Plusieurs cartes par pôle = meilleure calibration (le signal par pôle est
  /// agrégé au reveal).
  ///
  /// Dégrade proprement : sur les thèmes pauvres, on complète depuis le
  /// catalogue large (sources les plus suivies) ; un pôle sans candidat est
  /// simplement omis (moins de cartes).
  static List<SpanningSource> buildSpanningSet({
    required List<String> selectedThemes,
    required List<String> selectedSubtopics,
    required List<Source> allSources,
    int maxCards = 10,
    int perPole = 2,
  }) {
    final curated = allSources.where((s) => s.isCurated).toList();
    if (curated.isEmpty) return const [];

    bool matchesThemes(Source s) {
      if (selectedThemes.isEmpty && selectedSubtopics.isEmpty) return true;
      if (s.theme != null && selectedThemes.contains(s.theme)) return true;
      if (s.secondaryThemes.any(selectedThemes.contains)) return true;
      if (s.granularTopics.any(selectedSubtopics.contains)) return true;
      return false;
    }

    final matched = curated.where(matchesThemes).toList();
    final matchedIds = matched.map((s) => s.id).toSet();

    // Pool = matchés d'abord, complétés par le reste du curé (par audience)
    // pour garantir un set étalé même sur thèmes pauvres.
    var pool = [...matched];
    if (pool.length < maxCards) {
      final extra = curated.where((s) => !matchedIds.contains(s.id)).toList()
        ..sort((a, b) => b.followerCount.compareTo(a.followerCount));
      pool = [...pool, ...extra];
    }

    final targetPerspectiveBiases = _oppositeBiases(matched);

    final used = <String>{};
    final result = <SpanningSource>[];

    int byFollowers(Source a, Source b) =>
        b.followerCount.compareTo(a.followerCount);

    // Sélectionne la meilleure source d'un pôle, en préférant les sources
    // matchées thématiquement avant de puiser dans le catalogue large.
    void pick(
      SwipeAxisPole pole,
      bool Function(Source) test,
      int Function(Source, Source) rank,
    ) {
      if (result.length >= maxCards) return;
      final candidates =
          pool.where((s) => !used.contains(s.id) && test(s)).toList()
            ..sort((a, b) {
              final am = matchedIds.contains(a.id) ? 1 : 0;
              final bm = matchedIds.contains(b.id) ? 1 : 0;
              if (am != bm) return bm - am; // matchés d'abord
              return rank(a, b);
            });
      if (candidates.isEmpty) return;
      used.add(candidates.first.id);
      result.add(SpanningSource(source: candidates.first, pole: pole));
    }

    // Un "picker" par pôle, appelés en round-robin sur [perPole] tours : on
    // remplit d'abord 1 par pôle (set bien étalé), puis on approfondit.
    final pickers = <void Function()>[
      // 1. Indépendant : forte indépendance ou posture alternative/spécialisée.
      () => pick(
            SwipeAxisPole.independent,
            (s) =>
                (s.scoreIndependence ?? 0) >= 0.6 ||
                s.biasStance == 'alternative' ||
                s.biasStance == 'specialized',
            (a, b) =>
                (b.scoreIndependence ?? 0).compareTo(a.scoreIndependence ?? 0),
          ),
      // 2. Fond : tier deep.
      () => pick(SwipeAxisPole.deep, (s) => s.sourceTier == 'deep', byFollowers),
      // 3. Référence établie : fiabilité haute + faible indépendance.
      () => pick(
            SwipeAxisPole.established,
            (s) =>
                s.reliabilityScore == 'high' &&
                (s.scoreIndependence ?? 1) <= 0.5,
            (a, b) =>
                (a.scoreIndependence ?? 1).compareTo(b.scoreIndependence ?? 1),
          ),
      // 4. Actu directe : tier mainstream.
      () => pick(
            SwipeAxisPole.mainstream,
            (s) => s.sourceTier == 'mainstream',
            byFollowers,
          ),
      // 5. Perspective : bord opposé à la majorité matchée.
      () => pick(
            SwipeAxisPole.perspective,
            (s) => targetPerspectiveBiases.contains(s.biasStance),
            byFollowers,
          ),
    ];

    for (var round = 0; round < perPole; round++) {
      for (final p in pickers) {
        if (result.length >= maxCards) break;
        p();
      }
    }

    // Complète si des pôles manquaient (thèmes pauvres) avec les sources
    // matchées restantes les plus suivies (pôle neutre = actu directe).
    if (result.length < maxCards) {
      final fillers = pool.where((s) => !used.contains(s.id)).toList()
        ..sort(byFollowers);
      for (final s in fillers) {
        if (result.length >= maxCards) break;
        used.add(s.id);
        result.add(
          SpanningSource(source: s, pole: SwipeAxisPole.mainstream),
        );
      }
    }

    return result;
  }

  /// Pôle(s) d'axe *intrinsèque(s)* d'une source — utilisé pour généraliser le
  /// signal du swipe à toutes les sources d'un même pôle. Une source peut
  /// appartenir à plusieurs pôles (ex. fond + indépendant).
  ///
  /// Le pôle `perspective` est *relatif* (bord opposé à la majorité matchée) et
  /// n'est donc pas classé ici : on le laisse à la section perspective dédiée.
  static Set<SwipeAxisPole> _polesForSource(Source s) {
    final poles = <SwipeAxisPole>{};
    if (s.sourceTier == 'deep') poles.add(SwipeAxisPole.deep);
    if (s.sourceTier == 'mainstream') poles.add(SwipeAxisPole.mainstream);
    if ((s.scoreIndependence ?? 0) >= 0.6 ||
        s.biasStance == 'alternative' ||
        s.biasStance == 'specialized') {
      poles.add(SwipeAxisPole.independent);
    }
    if (s.reliabilityScore == 'high' && (s.scoreIndependence ?? 1) <= 0.5) {
      poles.add(SwipeAxisPole.established);
    }
    return poles;
  }

  /// Agrège les votes du swipe par pôle d'axe : +1 par source likée, -1 par
  /// source rejetée, réparti sur chacun de ses pôles intrinsèques.
  static Map<SwipeAxisPole, int> _aggregatePoleVotes(
    List<Source> sources,
    Set<String> liked,
    Set<String> disliked,
  ) {
    if (liked.isEmpty && disliked.isEmpty) return const {};
    final votes = <SwipeAxisPole, int>{};
    for (final s in sources) {
      final delta = liked.contains(s.id)
          ? 1
          : (disliked.contains(s.id) ? -1 : 0);
      if (delta == 0) continue;
      for (final pole in _polesForSource(s)) {
        votes[pole] = (votes[pole] ?? 0) + delta;
      }
    }
    return votes;
  }

  /// Biais "opposés" à la majorité d'un ensemble de sources (pour le pôle
  /// perspective). Ensemble équilibré ou sans info → les deux bords.
  static Set<String> _oppositeBiases(List<Source> sources) {
    int left = 0;
    int right = 0;
    for (final s in sources) {
      if (s.biasStance == 'left' || s.biasStance == 'center-left') left++;
      if (s.biasStance == 'right' || s.biasStance == 'center-right') right++;
    }
    if (left > right) return {'right', 'center-right'};
    if (right > left) return {'left', 'center-left'};
    return {'left', 'center-left', 'right', 'center-right'};
  }
}

class _ScoreResult {
  final int score;
  final String reason;
  final List<RecommendationTag> tags;
  const _ScoreResult({
    required this.score,
    required this.reason,
    this.tags = const [],
  });
}
