import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../models/topic_models.dart';
import '../providers/custom_topics_provider.dart';
import '../widgets/theme_section.dart';

/// Settings screen for managing custom topic subscriptions.
///
/// Groups followed topics by parent theme (slug_parent) in ExpansionTiles,
/// with in-situ suggestions per theme.
class MyInterestsScreen extends ConsumerWidget {
  const MyInterestsScreen({super.key});

  // Uses getTopicMacroTheme() and macroThemeOrder from topic_labels.dart

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final topicsAsync = ref.watch(customTopicsProvider);

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        title: const Text('Mes Interets'),
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
              'Impossible de charger vos interets.',
              style: textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
          ),
        ),
        data: (topics) {
          // Group topics by macro group
          final grouped = <String, List<_GroupedTheme>>{};
          for (final topic in topics) {
            final slug = topic.slugParent ?? '';
            final macroGroup = getTopicMacroTheme(slug) ?? 'Autres';
            grouped.putIfAbsent(macroGroup, () => []);

            // Find or create the theme entry within this group
            final existing = grouped[macroGroup]!
                .where((g) => g.slug == slug)
                .toList();
            if (existing.isNotEmpty) {
              existing.first.topics.add(topic);
            } else {
              grouped[macroGroup]!.add(_GroupedTheme(
                slug: slug,
                label: getTopicLabel(slug),
                topics: [topic],
              ));
            }
          }

          // Also add groups with no followed topics (for suggestions)
          final existingSlugs = topics.map((t) => t.slugParent ?? '').toSet();
          for (final slug in topicSlugToLabel.keys) {
            if (!existingSlugs.contains(slug)) {
              final macroGroup = getTopicMacroTheme(slug) ?? 'Autres';
              grouped.putIfAbsent(macroGroup, () => []);
            }
          }

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
                        'Ton algorithme, tes regles.',
                        style: textTheme.displaySmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space2),
                      Text(
                        'Facteur apprend de tes lectures. Ajuste tes sujets pour un feed qui te ressemble.',
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),

                // Theme sections
                ...macroThemeOrder
                    .where((group) => grouped.containsKey(group))
                    .map((group) {
                  final themes = grouped[group]!;
                  if (themes.isEmpty) {
                    // Group with no followed topics — show with just suggestions
                    // Pick first slug from this group for suggestions
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
                  // If multiple sub-themes, render one section per group
                  // with all topics aggregated
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
