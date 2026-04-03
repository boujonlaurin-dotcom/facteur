import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/topic_models.dart';
import 'topic_priority_slider.dart';

/// A row displaying a followed custom topic with its priority slider.
class TopicRow extends StatelessWidget {
  final UserTopicProfile topic;
  final ValueChanged<double> onPriorityChanged;
  final VoidCallback? onUnfollow;
  final VoidCallback? onMute;

  const TopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
    this.onUnfollow,
    this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: 2,
      ),
      child: Row(
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: Color(0xFFE07A5F),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
          Expanded(
            child: Text(
              topic.name,
              style: textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (onMute != null)
            GestureDetector(
              onTap: onMute,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                  size: 14,
                  color: colors.textTertiary,
                ),
              ),
            ),
          if (onUnfollow != null)
            GestureDetector(
              onTap: onUnfollow,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: Icon(
                  PhosphorIcons.minusCircle(PhosphorIconsStyle.regular),
                  size: 14,
                  color: const Color(0xFFE07A5F),
                ),
              ),
            ),
          TopicPrioritySlider(
            currentMultiplier: topic.priorityMultiplier,
            onChanged: onPriorityChanged,
          ),
        ],
      ),
    );
  }
}

/// Wraps a [TopicRow] in a [Dismissible] for swipe-to-unfollow.
class DismissibleTopicRow extends StatelessWidget {
  final UserTopicProfile topic;
  final ValueChanged<double> onPriorityChanged;
  final VoidCallback? onUnfollow;
  final VoidCallback? onMute;

  const DismissibleTopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
    this.onUnfollow,
    this.onMute,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Dismissible(
      key: ValueKey(topic.id),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: FacteurSpacing.space4),
        color: colors.textTertiary.withValues(alpha: 0.2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.minusCircle(PhosphorIconsStyle.regular),
              color: colors.textSecondary,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              'Ne plus suivre',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async => true,
      onDismissed: (_) => onUnfollow?.call(),
      child: TopicRow(
        topic: topic,
        onPriorityChanged: onPriorityChanged,
        onUnfollow: onUnfollow,
        onMute: onMute,
      ),
    );
  }
}
