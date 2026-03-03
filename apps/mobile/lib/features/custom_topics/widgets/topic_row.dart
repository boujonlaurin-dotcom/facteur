import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/topic_models.dart';
import 'topic_priority_slider.dart';

/// A row displaying a followed custom topic with its priority slider.
class TopicRow extends StatelessWidget {
  final UserTopicProfile topic;
  final ValueChanged<double> onPriorityChanged;

  const TopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      child: Row(
        children: [
          Icon(
            PhosphorIcons.pushPin(PhosphorIconsStyle.fill),
            size: 14,
            color: const Color(0xFFE07A5F),
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
          ),
        ],
      ),
    );
  }
}

/// Wraps a [TopicRow] in a [Dismissible] for swipe-to-delete with confirmation.
class DismissibleTopicRow extends StatelessWidget {
  final UserTopicProfile topic;
  final ValueChanged<double> onPriorityChanged;
  final VoidCallback onUnfollow;

  const DismissibleTopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
    required this.onUnfollow,
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
        color: colors.error,
        child: const Icon(
          Icons.delete_outline,
          color: Colors.white,
          size: 20,
        ),
      ),
      confirmDismiss: (_) async {
        return showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Ne plus suivre ce sujet ?'),
            content: Text('${topic.name} sera retire de vos interets.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                child: const Text('Annuler'),
              ),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'Supprimer',
                  style: TextStyle(color: colors.error),
                ),
              ),
            ],
          ),
        );
      },
      onDismissed: (_) => onUnfollow(),
      child: TopicRow(
        topic: topic,
        onPriorityChanged: onPriorityChanged,
      ),
    );
  }
}
