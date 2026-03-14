import 'package:flutter/material.dart';

import '../models/digest_models.dart';
import 'intro_text.dart';
import 'topic_section.dart';
import 'transition_text.dart';

/// Assembles the editorial layout for a single subject:
/// IntroText + TopicSection (cards only) + TransitionText.
class EditorialSubjectBlock extends StatelessWidget {
  final DigestTopic topic;
  final bool isLast;
  final void Function(DigestItem) onArticleTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final void Function(DigestItem)? onSwipeDismiss;
  final String? activeDismissalId;
  final VoidCallback? onDismissUndo;
  final VoidCallback? onDismissAutoResolve;
  final VoidCallback? onDismissMuteSource;
  final void Function(String topic)? onDismissMuteTopic;

  const EditorialSubjectBlock({
    super.key,
    required this.topic,
    required this.isLast,
    required this.onArticleTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
    this.onSwipeDismiss,
    this.activeDismissalId,
    this.onDismissUndo,
    this.onDismissAutoResolve,
    this.onDismissMuteSource,
    this.onDismissMuteTopic,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (topic.introText != null) IntroText(text: topic.introText!),
        TopicSection(
          topic: topic,
          editorialMode: true,
          onArticleTap: onArticleTap,
          onLike: onLike,
          onSave: onSave,
          onNotInterested: onNotInterested,
          onSwipeDismiss: onSwipeDismiss,
          activeDismissalId: activeDismissalId,
          onDismissUndo: onDismissUndo,
          onDismissAutoResolve: onDismissAutoResolve,
          onDismissMuteSource: onDismissMuteSource,
          onDismissMuteTopic: onDismissMuteTopic,
        ),
        if (!isLast && topic.transitionText != null)
          TransitionText(text: topic.transitionText!),
      ],
    );
  }
}
