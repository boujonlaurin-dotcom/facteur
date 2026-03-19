import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../../core/api/providers.dart';
import '../providers/algorithm_profile_provider.dart';
import '../providers/custom_topics_provider.dart';
import '../widgets/topic_priority_slider.dart';

/// Terracotta accent color for custom topics.
const Color _terracotta = Color(0xFFE07A5F);

/// Screen displaying articles for a specific topic.
///
/// Shows a header with follow/unfollow + priority controls,
/// and a list of articles related to that topic.
class TopicExplorerScreen extends ConsumerWidget {
  final String topicSlug;
  final String? topicName;
  final List<Content>? initialArticles;

  const TopicExplorerScreen({
    super.key,
    required this.topicSlug,
    this.topicName,
    this.initialArticles,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final displayName = topicName ?? getTopicLabel(topicSlug);

    // Find parent theme label for subtitle
    final parentLabel = _getParentThemeLabel(topicSlug);

    // Check if this topic is followed
    final topicsAsync = ref.watch(customTopicsProvider);
    final topics = topicsAsync.valueOrNull ?? [];
    final matchingTopics = topics.where(
      (t) =>
          t.slugParent == topicSlug ||
          t.name.toLowerCase() == displayName.toLowerCase(),
    );
    final isFollowed = matchingTopics.isNotEmpty;
    final matchedTopic = isFollowed ? matchingTopics.first : null;
    final articles = initialArticles ?? [];

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              displayName,
              style: textTheme.displaySmall?.copyWith(fontSize: 18),
            ),
            if (parentLabel != null)
              Text(
                parentLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                ),
              ),
          ],
        ),
      ),
      body: Column(
        children: [
          // Action header
          Container(
            margin: const EdgeInsets.all(FacteurSpacing.space4),
            padding: const EdgeInsets.all(FacteurSpacing.space4),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              border: Border.all(color: colors.surfaceElevated),
            ),
            child: isFollowed && matchedTopic != null
                ? Row(
                    children: [
                      Icon(
                        PhosphorIcons.check(PhosphorIconsStyle.bold),
                        size: 16,
                        color: _terracotta,
                      ),
                      const SizedBox(width: FacteurSpacing.space2),
                      Text(
                        'Suivi',
                        style: textTheme.labelLarge?.copyWith(
                          color: _terracotta,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        'Priorité :',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(width: FacteurSpacing.space2),
                      Builder(builder: (context) {
                        final algoProfile = ref.watch(algorithmProfileProvider).valueOrNull;
                        final topicSlug = matchedTopic.slugParent;
                        final topicUsage = algoProfile != null &&
                                topicSlug != null &&
                                algoProfile.subtopicWeights.containsKey(topicSlug)
                            ? algoProfile.normalizeWeight(
                                algoProfile.subtopicWeights[topicSlug]!)
                            : null;
                        return TopicPrioritySlider(
                          currentMultiplier: matchedTopic.priorityMultiplier,
                          onChanged: (multiplier) async {
                            try {
                              await ref
                                  .read(customTopicsProvider.notifier)
                                  .updatePriority(
                                      matchedTopic.id, multiplier);
                            } on DioException catch (e) {
                              if (context.mounted) {
                                final detail = e.response?.data;
                                final msg = (detail is Map &&
                                        detail['detail'] is String)
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
                          usageWeight: topicUsage,
                          onReset: topicUsage != null
                              ? () async {
                                  final client = ref.read(apiClientProvider);
                                  await client.post('/users/subtopics/$topicSlug/reset');
                                  ref.invalidate(algorithmProfileProvider);
                                }
                              : null,
                        );
                      }),
                    ],
                  )
                : Column(
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            ref
                                .read(customTopicsProvider.notifier)
                                .followTopic(displayName);
                          },
                          icon: Icon(
                            PhosphorIcons.plus(),
                            size: 16,
                            color: Colors.white,
                          ),
                          label: const Text(
                            'Suivre ce sujet',
                            style: TextStyle(color: Colors.white),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _terracotta,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(
                                FacteurRadius.small,
                              ),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: FacteurSpacing.space1),
                      Text(
                        'Recevez plus d\'articles sur $displayName',
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
          ),

          // Article count
          if (articles.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space4,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '${articles.length} article${articles.length > 1 ? 's' : ''} recent${articles.length > 1 ? 's' : ''}',
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),

          const SizedBox(height: FacteurSpacing.space2),

          // Article list
          Expanded(
            child: articles.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          PhosphorIcons.newspaper(),
                          size: 48,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(height: FacteurSpacing.space3),
                        Text(
                          'Aucun article disponible',
                          style: textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: FacteurSpacing.space1),
                        Text(
                          'Les articles sur ce sujet apparaîtront ici.',
                          style: textTheme.bodySmall?.copyWith(
                            color: colors.textTertiary,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space4,
                    ),
                    itemCount: articles.length,
                    itemBuilder: (context, index) {
                      final article = articles[index];
                      return Padding(
                        padding: const EdgeInsets.only(
                          bottom: FacteurSpacing.space3,
                        ),
                        child: FeedCard(
                          content: article,
                          onTap: () {
                            // Navigate to article detail
                            Navigator.of(context).pushNamed(
                              '/feed/content/${article.id}',
                            );
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// Get parent theme display label for the subtitle.
  /// Uses the centralized mapping from topic_labels.dart.
  String? _getParentThemeLabel(String slug) => getTopicMacroTheme(slug);
}
