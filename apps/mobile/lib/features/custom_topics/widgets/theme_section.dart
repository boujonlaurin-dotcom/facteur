import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../models/topic_models.dart';
import '../providers/custom_topics_provider.dart';
import 'suggestion_row.dart';
import 'topic_row.dart';

/// A collapsible section grouping followed topics and suggestions under a macro theme.
class ThemeSection extends ConsumerWidget {
  final String themeSlug;
  final String themeLabel;
  final List<UserTopicProfile> followedTopics;

  const ThemeSection({
    super.key,
    required this.themeSlug,
    required this.themeLabel,
    required this.followedTopics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.surfaceElevated),
        ),
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: true,
            tilePadding: const EdgeInsets.symmetric(
              horizontal: FacteurSpacing.space4,
              vertical: FacteurSpacing.space1,
            ),
            childrenPadding: const EdgeInsets.only(
              bottom: FacteurSpacing.space3,
            ),
            title: Text(
              themeLabel.toUpperCase(),
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                letterSpacing: 1.5,
                fontWeight: FontWeight.w600,
              ),
            ),
            children: [
              // Followed topics
              ...followedTopics.map((topic) => DismissibleTopicRow(
                    topic: topic,
                    onPriorityChanged: (multiplier) {
                      ref
                          .read(customTopicsProvider.notifier)
                          .updatePriority(topic.id, multiplier);
                    },
                    onUnfollow: () {
                      ref
                          .read(customTopicsProvider.notifier)
                          .unfollowTopic(topic.id);
                    },
                  )),

              // Suggestions divider + suggestions
              _SuggestionsBlock(
                themeSlug: themeSlug,
                followedTopics: followedTopics,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SuggestionsBlock extends ConsumerWidget {
  final String themeSlug;
  final List<UserTopicProfile> followedTopics;

  const _SuggestionsBlock({
    required this.themeSlug,
    required this.followedTopics,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final suggestionsAsync = ref.watch(topicSuggestionsProvider(themeSlug));

    return suggestionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (suggestions) {
        // Filter out already-followed topics
        final followedNames =
            followedTopics.map((t) => t.name.toLowerCase()).toSet();
        final available = suggestions
            .where((s) => !followedNames.contains(s.toLowerCase()))
            .take(3)
            .toList();

        if (available.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space4,
                vertical: FacteurSpacing.space2,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: colors.textTertiary.withValues(alpha: 0.2),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space2,
                    ),
                    child: Text(
                      'Suggestions',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 10,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: colors.textTertiary.withValues(alpha: 0.2),
                    ),
                  ),
                ],
              ),
            ),
            ...available.map((name) => SuggestionRow(
                  name: name,
                  onFollow: () {
                    ref
                        .read(customTopicsProvider.notifier)
                        .followTopic(name);
                  },
                )),
          ],
        );
      },
    );
  }
}
