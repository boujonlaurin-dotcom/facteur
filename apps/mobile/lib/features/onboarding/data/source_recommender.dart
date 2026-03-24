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
  static SourceRecommendation recommend({
    required List<String> selectedThemes,
    required List<String> selectedSubtopics,
    required List<Source> allSources,
    List<String> objectives = const [],
  }) {
    final curated = allSources.where((s) => s.isCurated).toList();

    final hasNoise = objectives.contains('noise');
    final hasBias = objectives.contains('bias');
    final hasAnxiety = objectives.contains('anxiety');

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

    return SourceRecommendation(
      matched: matchedSources,
      perspective: perspectiveSources,
      gems: gemSources,
      catalog: catalogRecommended,
    );
  }

  static _ScoreResult _scoreSource({
    required Source source,
    required List<String> themes,
    required List<String> subtopics,
    required bool hasNoise,
    required bool hasBias,
    required bool hasAnxiety,
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
    // Determine majority bias of matched sources
    int leftCount = 0;
    int rightCount = 0;
    for (final r in matched) {
      final bias = r.source.biasStance;
      if (bias == 'left' || bias == 'center-left') leftCount++;
      if (bias == 'right' || bias == 'center-right') rightCount++;
    }

    // Look for opposite bias
    final Set<String> targetBiases;
    if (leftCount > rightCount) {
      targetBiases = {'right', 'center-right'};
    } else if (rightCount > leftCount) {
      targetBiases = {'left', 'center-left'};
    } else {
      // Balanced or no bias info — show both sides
      targetBiases = {'left', 'center-left', 'right', 'center-right'};
    }

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
