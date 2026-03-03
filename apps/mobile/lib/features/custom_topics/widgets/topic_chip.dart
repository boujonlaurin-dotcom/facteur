import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../feed/models/content_model.dart';
import '../providers/custom_topics_provider.dart';
import 'topic_priority_slider.dart';

/// Terracotta accent color for custom topics.
const Color _terracotta = Color(0xFFE07A5F);

/// Topic chip in the feed card footer.
///
/// - Followed: terracotta bg 10%, border, pushPin icon.
/// - Unfollowed: surface bg, textSecondary, inline [+ Suivre] CTA.
/// Tap on label opens the topic explorer modal sheet.
class TopicChip extends ConsumerWidget {
  final Content content;

  const TopicChip({
    super.key,
    required this.content,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (content.topics.isEmpty) return const SizedBox.shrink();

    final topicSlug = content.topics.first;
    final topicLabel = getTopicLabel(topicSlug);
    final colors = context.facteurColors;

    final topicsAsync = ref.watch(customTopicsProvider);
    final isFollowed = topicsAsync.valueOrNull?.any(
          (t) =>
              t.slugParent == topicSlug ||
              t.name.toLowerCase() == topicLabel.toLowerCase(),
        ) ??
        false;

    if (isFollowed) {
      // Followed state: grayed check icon, tap opens explorer sheet
      return GestureDetector(
        onTap: () => showTopicSheet(context, topicSlug, topicLabel),
        child: Container(
          padding: const EdgeInsets.all(6),
          child: Icon(
            PhosphorIcons.check(PhosphorIconsStyle.bold),
            size: 18,
            color: colors.textSecondary,
          ),
        ),
      );
    }

    // Unfollowed state: "+" CTA in terracotta, tap follows the topic
    return GestureDetector(
      onTap: () {
        ref.read(customTopicsProvider.notifier).followTopic(topicLabel);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$topicLabel ajouté'),
            duration: const Duration(seconds: 2),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.all(6),
        child: Icon(
          PhosphorIcons.plus(PhosphorIconsStyle.bold),
          size: 18,
          color: _terracotta,
        ),
      ),
    );
  }

  /// Opens the topic explorer modal sheet with blur backdrop.
  static void showTopicSheet(
    BuildContext context,
    String topicSlug,
    String topicLabel,
  ) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: TopicExplorerSheet(
          topicSlug: topicSlug,
          topicLabel: topicLabel,
        ),
      ),
    );
  }
}

/// Modal sheet showing topic info with follow/priority controls.
class TopicExplorerSheet extends ConsumerWidget {
  final String topicSlug;
  final String topicLabel;
  final List<Content>? initialArticles;

  const TopicExplorerSheet({
    super.key,
    required this.topicSlug,
    required this.topicLabel,
    this.initialArticles,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;

    final topicsAsync = ref.watch(customTopicsProvider);
    final topics = topicsAsync.valueOrNull ?? [];
    final matchingTopics = topics.where(
      (t) =>
          t.slugParent == topicSlug ||
          t.name.toLowerCase() == topicLabel.toLowerCase(),
    );
    final isFollowed = matchingTopics.isNotEmpty;
    final matchedTopic = isFollowed ? matchingTopics.first : null;

    final parentLabel = getTopicMacroTheme(topicSlug);
    final articles = initialArticles ?? [];

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Drag handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space4),

            // Topic name + parent theme
            Text(
              topicLabel,
              style: textTheme.displaySmall?.copyWith(
                fontSize: 20,
                fontWeight: FontWeight.w700,
              ),
            ),
            if (parentLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                parentLabel,
                style: textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  letterSpacing: 1.0,
                ),
              ),
            ],

            const SizedBox(height: FacteurSpacing.space4),

            // Follow / Priority control
            if (isFollowed && matchedTopic != null)
              Container(
                padding: const EdgeInsets.all(FacteurSpacing.space3),
                decoration: BoxDecoration(
                  color: _terracotta.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(FacteurRadius.medium),
                  border: Border.all(
                    color: _terracotta.withValues(alpha: 0.2),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      PhosphorIcons.pushPin(PhosphorIconsStyle.fill),
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
                      'Priorite :',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(width: FacteurSpacing.space2),
                    TopicPrioritySlider(
                      currentMultiplier: matchedTopic.priorityMultiplier,
                      onChanged: (multiplier) {
                        ref
                            .read(customTopicsProvider.notifier)
                            .updatePriority(matchedTopic.id, multiplier);
                      },
                    ),
                  ],
                ),
              )
            else
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    ref
                        .read(customTopicsProvider.notifier)
                        .followTopic(topicLabel);
                    Navigator.of(context).pop();
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('$topicLabel ajouté'),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                  icon: Icon(
                    PhosphorIcons.plus(),
                    size: 16,
                    color: Colors.white,
                  ),
                  label: const Text(
                    'Suivre ce sujet',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                      fontSize: 15,
                    ),
                  ),
                  style: FilledButton.styleFrom(
                    backgroundColor: colorScheme.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.medium),
                    ),
                  ),
                ),
              ),

            if (!isFollowed) ...[
              const SizedBox(height: FacteurSpacing.space2),
              Center(
                child: Text(
                  'Recevez plus d\'articles sur $topicLabel',
                  style: textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
                ),
              ),
            ],

            // Article count (if articles provided)
            if (articles.isNotEmpty) ...[
              const SizedBox(height: FacteurSpacing.space4),
              Divider(color: colors.textTertiary.withValues(alpha: 0.2)),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                '${articles.length} article${articles.length > 1 ? 's' : ''} recent${articles.length > 1 ? 's' : ''}',
                style: textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],

            // "Gerer mes interets" CTA
            const SizedBox(height: FacteurSpacing.space3),
            Center(
              child: TextButton.icon(
                onPressed: () {
                  Navigator.of(context).pop();
                  context.pushNamed(RouteNames.myInterests);
                },
                icon: Icon(
                  PhosphorIcons.gear(),
                  size: 14,
                  color: colors.textSecondary,
                ),
                label: Text(
                  'Gérer mes intérêts',
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),

            const SizedBox(height: FacteurSpacing.space2),
          ],
        ),
      ),
    );
  }

}
