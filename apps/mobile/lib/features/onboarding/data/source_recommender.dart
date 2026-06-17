import 'package:flutter/foundation.dart';

import '../../../config/topic_labels.dart';
import '../../sources/models/source_model.dart';
import '../onboarding_strings.dart';

/// Category of a recommended source.
enum SourceCategory { matched, perspective, gem, catalog }

/// Type of recommendation tag displayed on a source card.
enum RecommendationTagType {
  /// Theme or subtopic match (e.g., "Tech", "IA")
  topic,

  /// Spécialité dominante de la source ∈ sujets choisis ("Spécialisé en {X}").
  /// Cœur de l'effet « wow » : ≥1 spécialiste visible par sujet sélectionné.
  specialist,

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

  /// Spécialistes ajoutés par la garantie de couverture : pour chaque subtopic
  /// sélectionné non encore couvert par un spécialiste présent dans [matched],
  /// le meilleur spécialiste curé du pool (badge « Spécialisé en {X} »).
  /// Disjoint de [matched]/[perspective]/[gems]/[catalog].
  final List<RecommendedSource> specialists;

  /// IDs that should be pre-selected.
  Set<String> get preselectedIds => {
    ...specialists.map((r) => r.source.id),
    ...matched.map((r) => r.source.id),
    ...gems.map((r) => r.source.id),
  };

  const SourceRecommendation({
    required this.matched,
    required this.perspective,
    required this.gems,
    required this.catalog,
    this.specialists = const [],
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

/// Un bloc contigu de cartes du swipe partageant un même pôle d'axe, avec un
/// en-tête humain (« mix type + thème »). L'ordre des groupes est piloté par
/// les préférences déclarées (indépendance / profondeur) ; cf.
/// [SourceRecommender.buildSpanningGroups].
class SwipeGroup {
  final SwipeAxisPole pole;
  final String label;
  final List<SpanningSource> cards;
  const SwipeGroup({
    required this.pole,
    required this.label,
    required this.cards,
  });
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

  /// Bonus « sources productives » : favorise les médias qui publient vraiment
  /// (quotidien actif vs blog dormant), au volume sur 30 j. Tiers modestes
  /// (+2/+1) pour rester sous le match thématique (`+3`) — le volume affine,
  /// il ne remplace pas la pertinence. `articles30d == 0` (signal absent) =
  /// no-op, donc rétro-compatible avec les réponses sans le champ.
  static int _volumeBonus(int articles30d) {
    if (articles30d >= 90) return 2; // ≈ 3/jour, source très active
    if (articles30d >= 20) return 1; // ≈ 0,7/jour, source régulière
    return 0;
  }

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
      matchedSources.add(
        RecommendedSource(
          source: source,
          category: SourceCategory.matched,
          tags: result.tags,
          reason: result.reason,
          score: scored[source.id] ?? 0,
        ),
      );
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

    // 3bis. Garantie de couverture : ≥1 spécialiste visible par subtopic choisi.
    // Pour chaque subtopic non déjà couvert par un spécialiste dominant présent
    // dans `matched`, tire le meilleur spécialiste curé restant du pool.
    final specialistSources = _computeSpecialists(
      selectedSubtopics: selectedSubtopics,
      matched: matchedSources,
      allCurated: curated,
      usedIds: usedIds,
      scored: scored,
    );
    for (final r in specialistSources) {
      usedIds.add(r.source.id);
    }

    // 4. Catalog: everything else, alphabetical
    final catalogSources =
        curated.where((s) => !usedIds.contains(s.id)).toList()..sort(
          (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
        );

    final catalogRecommended = catalogSources
        .map(
          (s) => RecommendedSource(
            source: s,
            category: SourceCategory.catalog,
            reason: '',
          ),
        )
        .toList();

    // Tag « Similaire à {nom} » : raccroche quelques recos à une source aimée
    // AU SWIPE, seulement quand aucune raison plus spécifique n'est déjà
    // affichée. Pas le catalogue (déjà replié), pas les sources déjà suivies.
    final likedSources = curated.where((s) => likedSet.contains(s.id)).toList();
    final similarTagCounts = <String, int>{};

    List<RecommendedSource> withSimilarTag(List<RecommendedSource> list) {
      if (likedSources.isEmpty) return list;
      return list.map((r) {
        if (_hasSpecificTag(r.tags)) return r;
        final anchor = _similarAnchor(r.source, likedSources);
        if (anchor == null) return r;
        final count = similarTagCounts[anchor.id] ?? 0;
        if (count >= 2) return r;
        similarTagCounts[anchor.id] = count + 1;
        final tag = RecommendationTag(
          label: 'Similaire à ${anchor.name}',
          type: RecommendationTagType.similar,
        );
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
      specialists: withSimilarTag(specialistSources),
    );
  }

  static bool _hasSpecificTag(List<RecommendationTag> tags) {
    return tags.any((t) {
      return t.type == RecommendationTagType.specialist ||
          t.type == RecommendationTagType.topic ||
          t.type == RecommendationTagType.antiBruit ||
          t.type == RecommendationTagType.fiable;
    });
  }

  /// Garantit ≥1 carte « spécialiste » par subtopic sélectionné. Un subtopic est
  /// déjà couvert si une source de [matched] le porte comme **spécialité
  /// dominante** (`granularTopics.first`). Pour chaque subtopic restant, choisit
  /// le meilleur spécialiste curé non encore utilisé qui **contient** ce subtopic
  /// (dominant d'abord, puis meilleur score, fiabilité, volume). Une source n'est
  /// tirée que pour un seul subtopic (cartes distinctes -> chaque sujet a la
  /// sienne quand la data le permet).
  static List<RecommendedSource> _computeSpecialists({
    required List<String> selectedSubtopics,
    required List<RecommendedSource> matched,
    required List<Source> allCurated,
    required Set<String> usedIds,
    required Map<String, int> scored,
  }) {
    if (selectedSubtopics.isEmpty) return const [];

    final covered = <String>{};
    for (final r in matched) {
      final gt = r.source.granularTopics;
      if (gt.isNotEmpty && selectedSubtopics.contains(gt.first)) {
        covered.add(gt.first);
      }
    }

    final taken = <String>{...usedIds};
    final result = <RecommendedSource>[];

    for (final sub in selectedSubtopics) {
      if (covered.contains(sub)) continue;
      final candidates =
          allCurated
              .where(
                (s) => !taken.contains(s.id) && s.granularTopics.contains(sub),
              )
              .toList()
            ..sort((a, b) {
              final ad =
                  a.granularTopics.isNotEmpty && a.granularTopics.first == sub
                  ? 1
                  : 0;
              final bd =
                  b.granularTopics.isNotEmpty && b.granularTopics.first == sub
                  ? 1
                  : 0;
              if (ad != bd) return bd - ad; // spécialité dominante d'abord
              final byScore = (scored[b.id] ?? 0).compareTo(scored[a.id] ?? 0);
              if (byScore != 0) return byScore;
              final aRel = a.reliabilityScore == 'high' ? 1 : 0;
              final bRel = b.reliabilityScore == 'high' ? 1 : 0;
              if (aRel != bRel) return bRel - aRel;
              return b.articles30d.compareTo(a.articles30d);
            });
      if (candidates.isEmpty) continue;
      final best = candidates.first;
      taken.add(best.id);
      covered.add(sub);
      result.add(
        RecommendedSource(
          source: best,
          category: SourceCategory.matched,
          tags: [
            RecommendationTag(
              label: 'Spécialisé en ${getTopicLabel(sub)}',
              type: RecommendationTagType.specialist,
            ),
          ],
          reason: 'Parce que vous suivez ${getTopicLabel(sub)}',
          score: scored[best.id] ?? 0,
        ),
      );
    }
    return result;
  }

  /// Cherche la meilleure source aimée au swipe « similaire » à [s]. Deux
  /// signaux partagés sont requis parmi thème, sujet granulaire, tier et biais
  /// connu. Départage par `followerCount` desc.
  static Source? _similarAnchor(Source s, List<Source> likedSources) {
    Set<String> themesOf(Source x) => {
      if (x.theme != null) x.theme!,
      ...x.secondaryThemes,
    };

    final sThemes = themesOf(s);
    Source? best;
    for (final liked in likedSources) {
      if (liked.id == s.id) continue;
      var sharedSignals = 0;
      if (sThemes.intersection(themesOf(liked)).isNotEmpty) {
        sharedSignals++;
      }
      if (s.granularTopics
          .toSet()
          .intersection(liked.granularTopics.toSet())
          .isNotEmpty) {
        sharedSignals++;
      }
      if (s.sourceTier == liked.sourceTier) {
        sharedSignals++;
      }
      if (s.biasStance != 'unknown' && s.biasStance == liked.biasStance) {
        sharedSignals++;
      }
      if (sharedSignals < 2) continue;
      if (best == null || liked.followerCount > best.followerCount) {
        best = liked;
      }
    }
    return best;
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
      tags.add(
        RecommendationTag(
          label: getTopicLabel(source.theme!),
          type: RecommendationTagType.topic,
        ),
      );
    }

    // Secondary themes match (+1 each)
    for (final t in source.secondaryThemes) {
      if (themes.contains(t)) {
        score += 1;
        if (bestReason.isEmpty) {
          bestReason = getTopicLabel(t);
        }
        // Only add tag for first secondary theme to avoid clutter
        if (tags.where((t) => t.type == RecommendationTagType.topic).length <
            2) {
          tags.add(
            RecommendationTag(
              label: getTopicLabel(t),
              type: RecommendationTagType.topic,
            ),
          );
        }
      }
    }

    // Badge « spécialiste » : la spécialité *dominante* (1er granularTopic, =
    // top share après le re-tag backend) ∈ sujets choisis. Cœur de l'effet wow.
    final String? specialistSlug =
        source.granularTopics.isNotEmpty &&
            subtopics.contains(source.granularTopics.first)
        ? source.granularTopics.first
        : null;
    if (specialistSlug != null) {
      tags.add(
        RecommendationTag(
          label: 'Spécialisé en ${getTopicLabel(specialistSlug)}',
          type: RecommendationTagType.specialist,
        ),
      );
    }

    // Granular topics match subtopics (+2 each)
    for (final gt in source.granularTopics) {
      if (subtopics.contains(gt)) {
        score += 2;
        if (bestReasonScore <= 3) {
          bestReasonScore = 4;
          bestReason = getTopicLabel(gt);
        }
        // La spécialité dominante est déjà badgée « Spécialisé en X » : on ne
        // double pas avec un tag thème générique.
        if (gt == specialistSlug) continue;
        // Add subtopic tag (prefer over theme if more specific)
        if (tags.where((t) => t.type == RecommendationTagType.topic).length <
            2) {
          tags.add(
            RecommendationTag(
              label: getTopicLabel(gt),
              type: RecommendationTagType.topic,
            ),
          );
        }
      }
    }

    // Reliability bonus (+1)
    if (source.reliabilityScore == 'high') {
      score += 1;
    }

    // Volume bonus : favorise les sources productives (cf. _volumeBonus).
    score += _volumeBonus(source.articles30d);

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
      tags.add(
        const RecommendationTag(
          label: 'Anti-bruit',
          type: RecommendationTagType.antiBruit,
        ),
      );
    }

    // Source fiable: user worried about bias → tag reliable sources
    // Rule: source has high reliability score
    if (hasBias && source.reliabilityScore == 'high') {
      tags.add(
        const RecommendationTag(
          label: 'Source fiable',
          type: RecommendationTagType.fiable,
        ),
      );
    }

    // Serein: user worried about anxiety → tag sources with calm themes
    // Rule: source's primary theme is in the low-anxiety set
    if (hasAnxiety &&
        source.theme != null &&
        _sereinThemes.contains(source.theme)) {
      tags.add(
        const RecommendationTag(
          label: 'Peu anxiogène',
          type: RecommendationTagType.serein,
        ),
      );
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
        .where(
          (s) => !usedIds.contains(s.id) && targetBiases.contains(s.biasStance),
        )
        .toList();

    // Sort by reliability (prefer 'high')
    candidates.sort((a, b) {
      final aRel = a.reliabilityScore == 'high' ? 1 : 0;
      final bRel = b.reliabilityScore == 'high' ? 1 : 0;
      return bRel.compareTo(aRel);
    });

    return candidates
        .take(_maxPerspective)
        .map(
          (s) => RecommendedSource(
            source: s,
            category: SourceCategory.perspective,
            reason: 'Pour voir un autre point de vue',
          ),
        )
        .toList();
  }

  static List<RecommendedSource> _computeGems({
    required List<Source> allCurated,
    required Set<String> usedIds,
    required Map<String, int> scored,
  }) {
    // Debug: help diagnose missing Pépites section
    final allDeep = allCurated.where((s) => s.sourceTier == 'deep').toList();
    debugPrint(
      '[SourceRecommender] _computeGems: '
      '${allCurated.length} curated sources, '
      '${allDeep.length} deep-tier sources '
      '(${allDeep.map((s) => s.name).join(", ")})',
    );

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

    // Tiebreaker des pôles non spécialisés (fond / actu directe / perspective)
    // et des fillers : à match thématique égal, faire remonter les sources
    // *productives* (volume 30 j) avant de départager par audience. Aligne le
    // deck de swipe sur le biais « sources productives » du scoring.
    int byVolumeThenFollowers(Source a, Source b) {
      final v = b.articles30d.compareTo(a.articles30d);
      if (v != 0) return v;
      return b.followerCount.compareTo(a.followerCount);
    }

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
      () => pick(
        SwipeAxisPole.deep,
        (s) => s.sourceTier == 'deep',
        byVolumeThenFollowers,
      ),
      // 3. Référence établie : fiabilité haute + faible indépendance.
      () => pick(
        SwipeAxisPole.established,
        (s) =>
            s.reliabilityScore == 'high' && (s.scoreIndependence ?? 1) <= 0.5,
        (a, b) =>
            (a.scoreIndependence ?? 1).compareTo(b.scoreIndependence ?? 1),
      ),
      // 4. Actu directe : tier mainstream.
      () => pick(
        SwipeAxisPole.mainstream,
        (s) => s.sourceTier == 'mainstream',
        byVolumeThenFollowers,
      ),
      // 5. Perspective : bord opposé à la majorité matchée.
      () => pick(
        SwipeAxisPole.perspective,
        (s) => targetPerspectiveBiases.contains(s.biasStance),
        byVolumeThenFollowers,
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
        ..sort(byVolumeThenFollowers);
      for (final s in fillers) {
        if (result.length >= maxCards) break;
        used.add(s.id);
        result.add(SpanningSource(source: s, pole: SwipeAxisPole.mainstream));
      }
    }

    return result;
  }

  /// Organise le spanning set en **groupes contigus** par pôle d'axe, avec un
  /// en-tête humain par groupe, l'ordre des groupes étant piloté par les
  /// préférences déclarées.
  ///
  /// Fonction *pure* (testable) : s'appuie sur [buildSpanningSet] pour le choix
  /// des cartes (mêmes cartes ⇒ même calibration, le signal par pôle étant
  /// agrégé au reveal indépendamment de l'ordre), puis :
  /// - regroupe les cartes par pôle en préservant l'ordre d'apparition ;
  /// - ordonne les groupes selon [independencePref] (`independent` ⇒ mener avec
  ///   indépendants/fond ; `established` ⇒ mener avec références/grands médias)
  ///   et [depthPref] (`detailed` ⇒ remonter le fond). Le pôle `perspective`
  ///   ferme toujours la marche ;
  /// - libelle chaque groupe en « mix type + thème » : si le groupe est cohérent
  ///   sur un thème des prefs (thème dominant), spécialise (« Pour creuser … »),
  ///   sinon libellé par pôle.
  static List<SwipeGroup> buildSpanningGroups({
    required List<String> selectedThemes,
    required List<String> selectedSubtopics,
    required List<Source> allSources,
    String? independencePref,
    String? depthPref,
    int maxCards = 10,
    int perPole = 2,
  }) {
    final set = buildSpanningSet(
      selectedThemes: selectedThemes,
      selectedSubtopics: selectedSubtopics,
      allSources: allSources,
      maxCards: maxCards,
      perPole: perPole,
    );
    if (set.isEmpty) return const [];

    // Regroupe par pôle en préservant l'ordre d'apparition des pôles ET des
    // cartes (LinkedHashMap garde l'ordre d'insertion).
    final byPole = <SwipeAxisPole, List<SpanningSource>>{};
    for (final s in set) {
      (byPole[s.pole] ??= <SpanningSource>[]).add(s);
    }

    final orderedPoles = byPole.keys.toList()
      ..sort(
        (a, b) => _poleOrderWeight(
          a,
          independencePref,
          depthPref,
        ).compareTo(_poleOrderWeight(b, independencePref, depthPref)),
      );

    return [
      for (final pole in orderedPoles)
        SwipeGroup(
          pole: pole,
          label: _groupLabel(pole, byPole[pole]!, selectedThemes),
          cards: byPole[pole]!,
        ),
    ];
  }

  /// Poids d'ordonnancement d'un groupe (plus petit = plus tôt). `perspective`
  /// reste toujours en fin (poids élevé non touché par les prefs).
  static double _poleOrderWeight(
    SwipeAxisPole pole,
    String? independencePref,
    String? depthPref,
  ) {
    var w = switch (pole) {
      SwipeAxisPole.mainstream => 2.0,
      SwipeAxisPole.established => 2.5,
      SwipeAxisPole.deep => 3.0,
      SwipeAxisPole.independent => 4.0,
      SwipeAxisPole.perspective => 9.0,
    };
    if (independencePref == 'independent') {
      w = switch (pole) {
        SwipeAxisPole.independent => 0.0,
        SwipeAxisPole.deep => 1.0,
        SwipeAxisPole.mainstream => 5.0,
        SwipeAxisPole.established => 6.0,
        SwipeAxisPole.perspective => 9.0,
      };
    } else if (independencePref == 'established') {
      w = switch (pole) {
        SwipeAxisPole.established => 0.0,
        SwipeAxisPole.mainstream => 1.0,
        SwipeAxisPole.deep => 4.0,
        SwipeAxisPole.independent => 6.0,
        SwipeAxisPole.perspective => 9.0,
      };
    }
    // Préférence « analyse de fond » : remonte le fond (jamais devant
    // perspective, qui garde son poids élevé).
    if (depthPref == 'detailed' && pole == SwipeAxisPole.deep) {
      w -= 2.5;
    }
    return w;
  }

  /// Libellé d'un groupe : « mix type + thème ». Spécialise si le groupe est
  /// cohérent sur un thème des prefs (majorité stricte des cartes), sinon
  /// libellé par pôle. Le pôle `perspective` (relatif) n'est jamais thématisé.
  static String _groupLabel(
    SwipeAxisPole pole,
    List<SpanningSource> cards,
    List<String> selectedThemes,
  ) {
    if (pole != SwipeAxisPole.perspective && selectedThemes.isNotEmpty) {
      final themed = _dominantPrefTheme(cards, selectedThemes);
      if (themed != null) {
        final label = cards
            .firstWhere((c) => c.source.theme == themed)
            .source
            .getThemeLabel();
        final template = pole == SwipeAxisPole.deep
            ? OnboardingStrings.swipeGroupThemedDeep
            : OnboardingStrings.swipeGroupThemedDefault;
        return template.replaceFirst('%s', label);
      }
    }
    return switch (pole) {
      SwipeAxisPole.deep => OnboardingStrings.swipeGroupDeep,
      SwipeAxisPole.independent => OnboardingStrings.swipeGroupIndependent,
      SwipeAxisPole.established => OnboardingStrings.swipeGroupEstablished,
      SwipeAxisPole.mainstream => OnboardingStrings.swipeGroupMainstream,
      SwipeAxisPole.perspective => OnboardingStrings.swipeGroupPerspective,
    };
  }

  /// Thème dominant (parmi les prefs) d'un groupe de cartes : thème principal
  /// le plus fréquent qui appartient aux thèmes choisis, retenu seulement s'il
  /// couvre une **majorité stricte** des cartes du groupe (groupe « cohérent »).
  static String? _dominantPrefTheme(
    List<SpanningSource> cards,
    List<String> selectedThemes,
  ) {
    final counts = <String, int>{};
    for (final c in cards) {
      final t = c.source.theme;
      if (t != null && selectedThemes.contains(t)) {
        counts[t] = (counts[t] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return null;
    String? best;
    var bestCount = 0;
    counts.forEach((theme, count) {
      if (count > bestCount) {
        bestCount = count;
        best = theme;
      }
    });
    return bestCount * 2 > cards.length ? best : null;
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
