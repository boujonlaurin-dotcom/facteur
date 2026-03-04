import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../models/topic_models.dart';
import '../providers/custom_topics_provider.dart';
import '../providers/theme_priority_provider.dart';
import 'suggestion_row.dart';
import 'topic_priority_slider.dart';
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
    final themePriorities =
        ref.watch(themePriorityProvider).valueOrNull ?? <String, double>{};

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
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    '${getMacroThemeEmoji(themeLabel)} ${themeLabel.toUpperCase()}',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                TopicPrioritySlider(
                  currentMultiplier: themePriorities[themeLabel] ?? 1.0,
                  onChanged: (multiplier) async {
                    await setThemePriority(themeLabel, multiplier);
                    ref.invalidate(themePriorityProvider);
                  },
                ),
              ],
            ),
            children: [
              // Followed topics
              ...followedTopics.map((topic) => DismissibleTopicRow(
                    topic: topic,
                    onPriorityChanged: (multiplier) async {
                      try {
                        await ref
                            .read(customTopicsProvider.notifier)
                            .updatePriority(topic.id, multiplier);
                      } on DioException catch (e) {
                        if (context.mounted) {
                          final detail = e.response?.data;
                          final msg =
                              (detail is Map && detail['detail'] is String)
                                  ? detail['detail'] as String
                                  : 'Erreur lors de la mise à jour';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
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

class _SuggestionsBlock extends ConsumerStatefulWidget {
  final String themeSlug;
  final List<UserTopicProfile> followedTopics;

  const _SuggestionsBlock({
    required this.themeSlug,
    required this.followedTopics,
  });

  @override
  ConsumerState<_SuggestionsBlock> createState() => _SuggestionsBlockState();
}

class _SuggestionsBlockState extends ConsumerState<_SuggestionsBlock> {
  static const int _initialLimit = 3;
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final suggestionsAsync =
        ref.watch(topicSuggestionsProvider(widget.themeSlug));

    return suggestionsAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (suggestions) {
        // Filter out already-followed topics
        final followedNames =
            widget.followedTopics.map((t) => t.name.toLowerCase()).toSet();
        final followedSlugs = widget.followedTopics
            .map((t) => t.slugParent)
            .whereType<String>()
            .toSet();
        final available = suggestions
            .where((s) => !followedNames.contains(s.toLowerCase()))
            .toList();

        // Supplement with local slugs when API returns few suggestions
        if (available.length < 5) {
          final macroTheme = getTopicMacroTheme(widget.themeSlug);
          if (macroTheme != null) {
            final localSlugs = getSlugsForMacroTheme(macroTheme);
            for (final slug in localSlugs) {
              if (available.length >= 8) break;
              if (followedSlugs.contains(slug)) continue;
              final label = getTopicLabel(slug);
              if (followedNames.contains(label.toLowerCase())) continue;
              if (available.any(
                  (s) => s.toLowerCase() == label.toLowerCase())) {
                continue;
              }
              available.add(label);
            }
          }
        }

        if (available.isEmpty) return const SizedBox.shrink();

        final visible =
            _expanded ? available : available.take(_initialLimit).toList();
        final hasMore = available.length > _initialLimit;

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
            ...visible.map((name) => SuggestionRow(
                  name: name,
                  onFollow: () {
                    ref
                        .read(customTopicsProvider.notifier)
                        .followTopic(name);
                  },
                )),
            if (hasMore && !_expanded)
              GestureDetector(
                onTap: () => setState(() => _expanded = true),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space2,
                  ),
                  child: Text(
                    'Voir plus...',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}
