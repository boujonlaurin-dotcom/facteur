import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/ui/notification_service.dart';
import '../../feed/providers/feed_provider.dart';
import '../../custom_topics/providers/custom_topics_provider.dart';
import '../../sources/providers/sources_providers.dart';
import '../providers/learning_checkpoint_provider.dart';
import '../services/learning_checkpoint_analytics.dart';
import 'proposal_row.dart';

/// Carte « Construire ton flux · Cette semaine » injectée dans le feed en
/// position 3 lorsque les conditions de gating sont réunies.
class ConstruireSonFluxCard extends ConsumerStatefulWidget {
  const ConstruireSonFluxCard({super.key});

  @override
  ConsumerState<ConstruireSonFluxCard> createState() =>
      _ConstruireSonFluxCardState();
}

class _ConstruireSonFluxCardState
    extends ConsumerState<ConstruireSonFluxCard> {
  bool _shownTracked = false;

  @override
  Widget build(BuildContext context) {
    ref.listen<AsyncValue<LearningCheckpointState>>(
      learningCheckpointProvider,
      (prev, next) {
        final nextState = next.valueOrNull;
        if (nextState is LcApplied || nextState is LcSnoozed) {
          // Rafraîchir le feed + invalidations cross-providers après action.
          ref.invalidate(feedProvider);
          ref.invalidate(userSourcesProvider);
          ref.invalidate(customTopicsProvider);
        }
        if (nextState is LcApplied && mounted) {
          NotificationService.showSuccess(
            'Tes préférences sont mises à jour',
          );
        }
        if (nextState is LcError && mounted) {
          NotificationService.showError('Une erreur est survenue');
        }
      },
    );

    final asyncState = ref.watch(learningCheckpointProvider);
    final value = asyncState.valueOrNull;

    // Track shown une seule fois par transition hidden → visible.
    if (value is LcVisible && !_shownTracked) {
      _shownTracked = true;
      final snapshot = value.displayed;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        ref
            .read(learningCheckpointAnalyticsProvider)
            .trackShown(snapshot);
      });
    }

    if (value is LcVisible) {
      return _buildCard(context, visible: value);
    }
    if (value is LcApplying) {
      return _buildCard(context, visible: value.previous, isApplying: true);
    }
    if (value is LcError && value.previous != null) {
      return _buildCard(context, visible: value.previous!, hasError: true);
    }
    // LcHidden / LcApplied / LcSnoozed / loading → invisible.
    return const SizedBox.shrink();
  }

  Widget _buildCard(
    BuildContext context, {
    required LcVisible visible,
    bool isApplying = false,
    bool hasError = false,
  }) {
    final colors = context.facteurColors;
    final notifier = ref.read(learningCheckpointProvider.notifier);

    final remaining = visible.displayed
        .where((p) => !visible.dismissedIds.contains(p.id))
        .toList();

    return Container(
      key: const ValueKey('construire_son_flux_card'),
      margin: const EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space4,
        vertical: FacteurSpacing.space2,
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardHeader(colors: colors),
          const SizedBox(height: FacteurSpacing.space3),
          Column(
            children: [
              for (final p in remaining)
                ProposalRow(
                  key: ValueKey('proposal_${p.id}'),
                  proposal: p,
                  isExpanded: visible.expandedRowId == p.id,
                  isDismissed: visible.dismissedIds.contains(p.id),
                  modifiedValue: visible.modifiedValues[p.id],
                ),
            ],
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: isApplying ? null : () => notifier.snooze(),
                child: const Text('Plus tard'),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              FilledButton(
                onPressed: isApplying ? null : () => notifier.validate(),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                ),
                child: isApplying
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : Text(hasError ? 'Réessayer' : 'Valider'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CardHeader extends StatelessWidget {
  final FacteurColors colors;
  const _CardHeader({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Text(
            'Construire ton flux · Cette semaine',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
