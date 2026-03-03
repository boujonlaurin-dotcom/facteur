import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../feed/models/content_model.dart';
import 'topic_chip.dart';

/// Chip shown below a representative article when a topic cluster exists.
///
/// Displays: `> N autres articles sur [Topic]`
/// Tap opens the topic explorer modal sheet with blur backdrop.
class ClusterChip extends StatelessWidget {
  final Content content;

  const ClusterChip({
    super.key,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    if (content.clusterHiddenCount == 0 || content.clusterTopic == null) {
      return const SizedBox.shrink();
    }

    final colors = context.facteurColors;
    final topicName = getTopicLabel(content.clusterTopic!);

    return GestureDetector(
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          backgroundColor: Colors.transparent,
          isScrollControlled: true,
          barrierColor: Colors.black.withValues(alpha: 0.5),
          builder: (ctx) => BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
            child: TopicExplorerSheet(
              topicSlug: content.clusterTopic!,
              topicLabel: topicName,
              initialArticles: content.clusterHiddenArticles,
            ),
          ),
        );
      },
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            top: BorderSide(
              color: colors.textSecondary.withValues(alpha: 0.1),
              width: 0.5,
            ),
          ),
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space3,
          vertical: FacteurSpacing.space2,
        ),
        child: Row(
          children: [
            Icon(
              PhosphorIcons.caretRight(PhosphorIconsStyle.bold),
              size: 12,
              color: colors.textSecondary,
            ),
            const SizedBox(width: FacteurSpacing.space2),
            Expanded(
              child: Text(
                '${content.clusterHiddenCount} autres articles sur $topicName',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(
              PhosphorIcons.arrowRight(),
              size: 14,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }
}
