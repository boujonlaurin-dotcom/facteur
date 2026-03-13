import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../models/topic_models.dart';
import '../providers/custom_topics_provider.dart';
import '../providers/theme_priority_provider.dart';
import '../widgets/theme_section.dart';

/// Settings screen for managing custom topic subscriptions.
///
/// Groups followed topics by parent theme (slug_parent) in ExpansionTiles,
/// with in-situ suggestions per theme.
/// Theme sections are sorted by max user priority on initial load only
/// (no dynamic reordering while the user is on the page).
class MyInterestsScreen extends ConsumerStatefulWidget {
  const MyInterestsScreen({super.key});

  @override
  ConsumerState<MyInterestsScreen> createState() => _MyInterestsScreenState();
}

class _MyInterestsScreenState extends ConsumerState<MyInterestsScreen> {
  /// Sorted group order, computed once on first data load.
  List<String>? _sortedGroups;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final topicsAsync = ref.watch(customTopicsProvider);
    final themePriorities =
        ref.watch(themePriorityProvider).valueOrNull ?? <String, double>{};

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Mes Intérêts'),
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        titleTextStyle: textTheme.displaySmall,
      ),
      body: topicsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            child: Text(
              'Impossible de charger vos intérêts.',
              style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (topics) {
          // Group topics by macro group
          final grouped = <String, List<_GroupedTheme>>{};
          for (final topic in topics) {
            final slug = topic.slugParent ?? _deriveSlugFromName(topic.name);
            final macroGroup = getTopicMacroTheme(slug) ?? 'Autres';
            grouped.putIfAbsent(macroGroup, () => []);

            // Find or create the theme entry within this group
            final existing = grouped[macroGroup]!
                .where((g) => g.slug == slug)
                .toList();
            if (existing.isNotEmpty) {
              existing.first.topics.add(topic);
            } else {
              final label = getTopicLabel(slug);
              grouped[macroGroup]!.add(_GroupedTheme(
                slug: slug,
                label: label.isNotEmpty ? label : topic.name,
                topics: [topic],
              ));
            }
          }

          // Also add groups with no followed topics (for suggestions)
          final existingSlugs = topics
              .map((t) => t.slugParent ?? _deriveSlugFromName(t.name))
              .toSet();
          for (final slug in topicSlugToLabel.keys) {
            if (!existingSlugs.contains(slug)) {
              final macroGroup = getTopicMacroTheme(slug) ?? 'Autres';
              grouped.putIfAbsent(macroGroup, () => []);
            }
          }

          // Compute sorted order only once (on initial page load).
          // Uses theme-level priorities (SharedPreferences) when available,
          // falling back to max individual topic priority.
          _sortedGroups ??= macroThemeOrder
              .where((group) => grouped.containsKey(group))
              .toList()
            ..sort((a, b) {
              final aPriority = themePriorities[a] ??
                  _maxPriority(grouped[a] ?? []);
              final bPriority = themePriorities[b] ??
                  _maxPriority(grouped[b] ?? []);
              if (aPriority != bPriority) {
                return bPriority.compareTo(aPriority);
              }
              return macroThemeOrder
                  .indexOf(a)
                  .compareTo(macroThemeOrder.indexOf(b));
            });

          return SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: FacteurSpacing.space8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Hero text
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space4,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Vos centres d\'intérêt',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space2),
                      Text(
                        'Vos centres d\'intérêt influencent le digest et le mode Pour vous.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Theme sections (order fixed on initial load)
                ..._sortedGroups!
                    .where((group) => grouped.containsKey(group))
                    .map((group) {
                  final themes = grouped[group]!;
                  if (themes.isEmpty) {
                    final groupSlugs = topicSlugToLabel.keys
                        .where((s) => getTopicMacroTheme(s) == group)
                        .toList();
                    if (groupSlugs.isEmpty) return const SizedBox.shrink();
                    return ThemeSection(
                      themeSlug: groupSlugs.first,
                      themeLabel: group,
                      followedTopics: const [],
                    );
                  }
                  final allTopics =
                      themes.expand((t) => t.topics).toList();
                  return ThemeSection(
                    themeSlug: themes.first.slug,
                    themeLabel: group,
                    followedTopics: allTopics,
                  );
                }),

                // Empty state
                if (topics.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4,
                      vertical: FacteurSpacing.space6,
                    ),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(
                            Icons.explore_outlined,
                            size: 48,
                            color: colors.textTertiary,
                          ),
                          const SizedBox(height: FacteurSpacing.space3),
                          Text(
                            'Aucun sujet suivi pour le moment.',
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: FacteurSpacing.space1),
                          Text(
                            'Explorez les suggestions ci-dessous pour personnaliser votre feed.',
                            style: textTheme.bodySmall?.copyWith(
                              color: colors.textTertiary,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Returns the max [priorityMultiplier] across all topics in the given themes.
/// Returns 0.0 if no topics exist (empty/suggestion-only groups sort last).
double _maxPriority(List<_GroupedTheme> themes) {
  double max = 0.0;
  for (final theme in themes) {
    for (final topic in theme.topics) {
      if (topic.priorityMultiplier > max) max = topic.priorityMultiplier;
    }
  }
  return max;
}

/// Reverse-lookup: finds a slug for a topic name from [topicSlugToLabel].
String _deriveSlugFromName(String name) {
  final lower = name.toLowerCase();
  for (final entry in topicSlugToLabel.entries) {
    if (entry.value.toLowerCase() == lower) {
      return entry.key;
    }
  }
  return '';
}

/// Helper to group topics by slug within a macro theme.
class _GroupedTheme {
  final String slug;
  final String label;
  final List<UserTopicProfile> topics;

  _GroupedTheme({
    required this.slug,
    required this.label,
    required this.topics,
  });
}
