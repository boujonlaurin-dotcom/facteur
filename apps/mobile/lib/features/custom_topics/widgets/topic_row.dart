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
  final double? usageWeight;
  final VoidCallback? onReset;

  const TopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
    this.onUnfollow,
    this.usageWeight,
    this.onReset,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
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
              TopicPrioritySlider(
                currentMultiplier: topic.priorityMultiplier,
                onChanged: onPriorityChanged,
                usageWeight: usageWeight,
                onReset: onReset,
              ),
            ],
          ),
        ),
        if (onUnfollow != null)
          Padding(
            padding: const EdgeInsets.only(
              left: FacteurSpacing.space4 + 6 + FacteurSpacing.space2,
            ),
            child: GestureDetector(
              onTap: onUnfollow,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIcons.minusCircle(PhosphorIconsStyle.regular),
                    size: 12,
                    color: colors.textTertiary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    'Ne plus suivre',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Wraps a [TopicRow] in a [Dismissible] for swipe-to-unfollow.
class DismissibleTopicRow extends StatelessWidget {
  final UserTopicProfile topic;
  final ValueChanged<double> onPriorityChanged;
  final VoidCallback? onUnfollow;
  final double? usageWeight;
  final VoidCallback? onReset;

  const DismissibleTopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
    this.onUnfollow,
    this.usageWeight,
    this.onReset,
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
      confirmDismiss: (_) async {
        onUnfollow?.call();
        return false; // Don't remove — let state rebuild handle removal
      },
      child: TopicRow(
        topic: topic,
        onPriorityChanged: onPriorityChanged,
        onUnfollow: onUnfollow,
        usageWeight: usageWeight,
        onReset: onReset,
      ),
    );
  }
}
