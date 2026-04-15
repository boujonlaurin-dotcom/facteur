import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/learning_proposal_model.dart';
import '../providers/learning_checkpoint_provider.dart';
import 'entity_toggle.dart';
import 'proposal_stats_panel.dart';
import 'source_priority_slider.dart';

/// Ligne unique d'une proposition dans la carte « Construire ton flux ».
class ProposalRow extends ConsumerWidget {
  final LearningProposal proposal;
  final bool isExpanded;
  final bool isDismissed;
  final num? modifiedValue;

  const ProposalRow({
    super.key,
    required this.proposal,
    this.isExpanded = false,
    this.isDismissed = false,
    this.modifiedValue,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final notifier = ref.read(learningCheckpointProvider.notifier);

    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _EntityIcon(proposal: proposal, colors: colors),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: RichText(
            text: TextSpan(
              style: TextStyle(color: colors.textPrimary, fontSize: 14),
              children: [
                TextSpan(
                  text: proposal.entityLabel,
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const TextSpan(text: ' — '),
                TextSpan(
                  text: proposal.justificationPhrase(),
                  style: TextStyle(color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: FacteurSpacing.space2),
        _targetValueWidget(notifier),
        const SizedBox(width: FacteurSpacing.space1),
        IconButton(
          icon: Icon(
            isExpanded
                ? PhosphorIcons.caretDown(PhosphorIconsStyle.regular)
                : PhosphorIcons.info(PhosphorIconsStyle.regular),
            size: 18,
            color: colors.textTertiary,
          ),
          tooltip: 'Détails de la proposition',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => notifier.toggleExpanded(proposal.id),
        ),
        IconButton(
          icon: Icon(
            PhosphorIcons.x(PhosphorIconsStyle.regular),
            size: 18,
            color: colors.textTertiary,
          ),
          tooltip: 'Ignorer cette proposition',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 48, minHeight: 48),
          onPressed: () => notifier.dismissItem(proposal.id),
        ),
      ],
    );

    return AnimatedSize(
      duration: FacteurDurations.fast,
      curve: Curves.easeInOut,
      child: Semantics(
        label: 'Proposition : ${proposal.entityLabel}',
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: FacteurSpacing.space1),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              row,
              if (isExpanded)
                ProposalStatsPanel(proposal: proposal),
            ],
          ),
        ),
      ),
    );
  }

  Widget _targetValueWidget(LearningCheckpointNotifier notifier) {
    switch (proposal.proposalType) {
      case ProposalType.sourcePriority:
        final current = (proposal.currentValue ?? 0).toInt();
        final proposed =
            (modifiedValue ?? proposal.proposedValue ?? 0).toInt();
        return SourcePrioritySlider(
          current: current,
          proposed: proposed,
          onChange: (v) => notifier.modifyValue(proposal.id, v),
        );
      case ProposalType.muteEntity:
        return EntityToggle(
          kind: EntityToggleKind.mute,
          preActive: !isDismissed,
          onChange: (active) {
            if (!active) notifier.dismissItem(proposal.id);
          },
        );
      case ProposalType.followEntity:
        return EntityToggle(
          kind: EntityToggleKind.follow,
          preActive: !isDismissed,
          onChange: (active) {
            if (!active) notifier.dismissItem(proposal.id);
          },
        );
      case ProposalType.unknown:
        return const SizedBox.shrink();
    }
  }
}

class _EntityIcon extends StatelessWidget {
  final LearningProposal proposal;
  final FacteurColors colors;

  const _EntityIcon({required this.proposal, required this.colors});

  @override
  Widget build(BuildContext context) {
    IconData iconData;
    switch (proposal.entityType) {
      case EntityType.source:
        iconData = PhosphorIcons.newspaper(PhosphorIconsStyle.regular);
        break;
      case EntityType.topic:
        iconData = PhosphorIcons.tag(PhosphorIconsStyle.regular);
        break;
      case EntityType.unknown:
        iconData = PhosphorIcons.question(PhosphorIconsStyle.regular);
        break;
    }
    return Icon(iconData, color: colors.primary, size: 20);
  }
}
