import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/widgets/nudge_inline_banner.dart';
import '../../../widgets/design/priority_slider.dart';
import '../../custom_topics/providers/algorithm_profile_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../providers/feed_provider.dart';

/// Bottom sheet for quick source adjustment (frequency slider + mute).
///
/// Opened on left-swipe of a feed card (Epic 12, Story 12.3).
/// Also reused by the contextual info button in chrono mode (Story 12.5).
class SourceAdjustSheet extends ConsumerStatefulWidget {
  final Source source;
  final VoidCallback? onMuted;

  const SourceAdjustSheet({
    super.key,
    required this.source,
    this.onMuted,
  });

  /// Show this sheet as a modal bottom sheet and return true if source was muted.
  static Future<bool?> show(
    BuildContext context, {
    required Source source,
    VoidCallback? onMuted,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SourceAdjustSheet(
        source: source,
        onMuted: onMuted,
      ),
    );
  }

  @override
  ConsumerState<SourceAdjustSheet> createState() => _SourceAdjustSheetState();
}

class _SourceAdjustSheetState extends ConsumerState<SourceAdjustSheet> {
  late double _currentMultiplier;
  bool _isMuting = false;
  bool _showPriorityExplainer = false;

  @override
  void initState() {
    super.initState();
    _currentMultiplier = widget.source.priorityMultiplier;
    _requestExplainerNudge();
  }

  Future<void> _requestExplainerNudge() async {
    final coordinator = ref.read(nudgeCoordinatorProvider);
    final active =
        await coordinator.request(NudgeIds.prioritySliderExplainer);
    if (!mounted) return;
    if (active == NudgeIds.prioritySliderExplainer) {
      setState(() => _showPriorityExplainer = true);
    }
  }

  Future<void> _dismissExplainer() async {
    if (!_showPriorityExplainer) return;
    final coordinator = ref.read(nudgeCoordinatorProvider);
    if (coordinator.activeId == NudgeIds.prioritySliderExplainer) {
      await coordinator.dismiss(markSeen: true);
    }
    if (mounted) {
      setState(() => _showPriorityExplainer = false);
    }
  }

  Future<void> _onSliderChanged(double newValue) async {
    setState(() => _currentMultiplier = newValue);
    try {
      await ref
          .read(userSourcesProvider.notifier)
          .updateWeight(widget.source.id, newValue);
      // Auto-refresh feed to reflect new diversification quotas
      unawaited(ref.read(feedProvider.notifier).refresh());
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Source mise à jour'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    } catch (_) {
      // Revert on error
      setState(() => _currentMultiplier = widget.source.priorityMultiplier);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors de la mise à jour')),
        );
      }
    }
  }

  Future<void> _onMute() async {
    if (_isMuting) return;
    setState(() => _isMuting = true);
    try {
      await ref
          .read(userSourcesProvider.notifier)
          .toggleMute(widget.source.id, false);
      widget.onMuted?.call();
      if (mounted) Navigator.pop(context, true);
    } catch (_) {
      setState(() => _isMuting = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Erreur lors du masquage')),
        );
      }
    }
  }

  void _openAllSettings() {
    Navigator.pop(context);
    // Navigate to Sources screen
    Navigator.of(context).pushNamed('/sources');
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final source = widget.source;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: colors.textTertiary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),

          // Source header: logo + name + theme
          Row(
            children: [
              // Source logo
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: source.logoUrl != null
                    ? Image.network(
                        source.logoUrl!,
                        width: 40,
                        height: 40,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _placeholderLogo(colors),
                      )
                    : _placeholderLogo(colors),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      source.name,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (source.theme != null)
                      Text(
                        source.theme!,
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),

          if (_showPriorityExplainer) ...[
            NudgeInlineBanner(
              body:
                  "Glissez pour ajuster l'importance de cette thématique dans votre digest — de minimale à essentielle.",
              icon: PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.regular),
              onDismiss: _dismissExplainer,
            ),
            const SizedBox(height: FacteurSpacing.space3),
          ],

          // Frequency label + slider
          Row(
            children: [
              Icon(
                PhosphorIcons.slidersHorizontal(PhosphorIconsStyle.regular),
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(
                'Fréquence',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: colors.textSecondary,
                ),
              ),
              const Spacer(),
              Builder(builder: (context) {
                final algoProfile = ref.watch(algorithmProfileProvider).valueOrNull;
                final sourceUsage = algoProfile?.sourceAffinities[widget.source.id];
                return PrioritySlider(
                  currentMultiplier: _currentMultiplier,
                  onChanged: _onSliderChanged,
                  usageWeight: sourceUsage,
                );
              }),
            ],
          ),
          const SizedBox(height: 20),

          // Mute button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isMuting ? null : _onMute,
              icon: Icon(
                PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                size: 18,
              ),
              label: const Text('Masquer cette source'),
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textSecondary,
                side: BorderSide(
                  color: colors.textTertiary.withOpacity(0.3),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          // Link to all settings
          TextButton(
            onPressed: _openAllSettings,
            child: Text(
              'Tous les réglages',
              style: TextStyle(
                fontSize: 13,
                color: colors.primary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _placeholderLogo(FacteurColors colors) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: colors.textTertiary.withOpacity(0.1),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Icon(
        PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
        size: 20,
        color: colors.textTertiary,
      ),
    );
  }
}
