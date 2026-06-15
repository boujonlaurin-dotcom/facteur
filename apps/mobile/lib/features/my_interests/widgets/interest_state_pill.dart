library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../models/user_interests_state.dart';
import '../providers/user_interests_provider.dart';
import '../providers/user_sources_state_provider.dart';
import 'interest_state_picker_sheet.dart';

/// Pastille pour un Sujet personnalisé (custom topic).
class CustomTopicStatePill extends ConsumerWidget {
  final String topicId;
  final String title;
  final bool fillWidth;

  const CustomTopicStatePill({
    super.key,
    required this.topicId,
    required this.title,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final interestsAsync = ref.watch(userInterestsProvider);
    final favoriteRef = CustomTopicFavoriteRef(id: topicId);
    final currentState = interestsAsync.valueOrNull?.stateOf(favoriteRef) ??
        InterestState.followed;

    return _StatePill(
      currentState: currentState,
      title: title,
      fillWidth: fillWidth,
      onSelect: (picked) async {
        try {
          await ref
              .read(userInterestsProvider.notifier)
              .setInterestState(favoriteRef, picked);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible de mettre à jour ce sujet.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
    );
  }
}

/// Pastille pour une Source.
class SourceStatePill extends ConsumerWidget {
  final String sourceId;
  final String title;
  final bool fillWidth;

  const SourceStatePill({
    super.key,
    required this.sourceId,
    required this.title,
    this.fillWidth = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(userSourcesStateProvider).valueOrNull;
    final currentState =
        state?.stateOf(sourceId) ?? InterestState.followed;

    return _StatePill(
      currentState: currentState,
      title: title,
      fillWidth: fillWidth,
      onSelect: (picked) async {
        try {
          await ref
              .read(userSourcesStateProvider.notifier)
              .setSourceState(sourceId, picked);
        } catch (_) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Impossible de mettre à jour cette source.'),
              duration: Duration(seconds: 3),
            ),
          );
        }
      },
    );
  }
}

class _StatePill extends StatelessWidget {
  final InterestState currentState;
  final String title;
  final bool fillWidth;
  final Future<void> Function(InterestState picked) onSelect;

  const _StatePill({
    required this.currentState,
    required this.title,
    required this.fillWidth,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final accent = currentState.accent(colors);

    final pill = Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: fillWidth ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: fillWidth
            ? MainAxisAlignment.center
            : MainAxisAlignment.start,
        children: [
          Icon(currentState.iconData, size: 14, color: accent),
          const SizedBox(width: 6),
          Text(
            currentState.label,
            style: textTheme.labelMedium?.copyWith(
              color: accent,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: () async {
        final picked = await InterestStatePickerSheet.show(
          context,
          title: title,
          currentState: currentState,
        );
        if (picked == null || picked == currentState) return;
        await onSelect(picked);
      },
      child: pill,
    );
  }
}
