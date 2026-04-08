import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/topic_models.dart';
import 'topic_priority_slider.dart';

/// A row displaying a followed custom topic with its priority slider.
class TopicRow extends StatelessWidget {
  final UserTopicProfile topic;
  final ValueChanged<double> onPriorityChanged;
  final double? usageWeight;
  final VoidCallback? onReset;
  final bool isMuted;
  final VoidCallback? onMute;
  final VoidCallback? onUnmute;

  const TopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
    this.usageWeight,
    this.onReset,
    this.isMuted = false,
    this.onMute,
    this.onUnmute,
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
            vertical: FacteurSpacing.space2,
          ),
          child: Row(
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: isMuted
                      ? colors.textTertiary.withValues(alpha: 0.4)
                      : const Color(0xFFE07A5F),
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: Text(
                  topic.name,
                  style: textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                    color: isMuted ? colors.textTertiary : null,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isMuted)
                TopicPrioritySlider(
                  currentMultiplier: topic.priorityMultiplier,
                  onChanged: onPriorityChanged,
                  usageWeight: usageWeight,
                  onReset: onReset,
                ),
            ],
          ),
        ),
        if (onMute != null || onUnmute != null)
          Padding(
            padding: const EdgeInsets.only(
              left: FacteurSpacing.space4 + 6 + FacteurSpacing.space2,
            ),
            child: GestureDetector(
              onTap: isMuted ? onUnmute : onMute,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isMuted
                          ? PhosphorIcons.eye(PhosphorIconsStyle.regular)
                          : PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      isMuted ? 'Afficher' : 'Masquer',
                      style: textTheme.labelSmall?.copyWith(
                        color: colors.textTertiary,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Wraps a [TopicRow] in a [Dismissible] for swipe-to-delete with confirmation.
class DismissibleTopicRow extends StatelessWidget {
  final UserTopicProfile topic;
  final ValueChanged<double> onPriorityChanged;
  final VoidCallback onUnfollow;
  final double? usageWeight;
  final VoidCallback? onReset;
  final bool isMuted;
  final VoidCallback? onMute;
  final VoidCallback? onUnmute;

  const DismissibleTopicRow({
    super.key,
    required this.topic,
    required this.onPriorityChanged,
    required this.onUnfollow,
    this.usageWeight,
    this.onReset,
    this.isMuted = false,
    this.onMute,
    this.onUnmute,
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
            content: Text('${topic.name} sera retiré de vos intérêts.'),
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
        usageWeight: usageWeight,
        onReset: onReset,
        isMuted: isMuted,
        onMute: onMute,
        onUnmute: onUnmute,
      ),
    );
  }
}
