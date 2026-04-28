import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/well_informed_prompt_provider.dart';

/// Prompt inline NPS-style posé dans le scroll du digest (Story 14.3).
///
/// Affiché conditionnellement via `wellInformedShouldShowProvider`. Se
/// re-cache immédiatement après submit/skip en invalidant le provider.
class WellInformedPrompt extends ConsumerStatefulWidget {
  const WellInformedPrompt({super.key, this.context = 'digest_inline'});

  final String context;

  @override
  ConsumerState<WellInformedPrompt> createState() => _WellInformedPromptState();
}

class _WellInformedPromptState extends ConsumerState<WellInformedPrompt>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl;
  bool _submitting = false;
  bool _shownTracked = false;

  @override
  void initState() {
    super.initState();
    _fadeCtrl = AnimationController(
      vsync: this,
      duration: FacteurDurations.medium,
    )..forward();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shownTracked) return;
      _shownTracked = true;
      unawaited(
        ref.read(wellInformedPromptControllerProvider).recordShown(),
      );
      unawaited(
        ref
            .read(analyticsServiceProvider)
            .trackWellInformedPromptShown(context: widget.context),
      );
    });
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit(int score) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    unawaited(HapticFeedback.mediumImpact());

    final controller = ref.read(wellInformedPromptControllerProvider);
    await controller.submit(score, context: widget.context);
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .trackWellInformedScoreSubmitted(
            score: score,
            context: widget.context,
          ),
    );

    if (mounted) {
      ref.invalidate(wellInformedShouldShowProvider);
    }
  }

  Future<void> _handleSkip() async {
    if (_submitting) return;
    unawaited(HapticFeedback.lightImpact());
    final controller = ref.read(wellInformedPromptControllerProvider);
    await controller.skip();
    unawaited(
      ref
          .read(analyticsServiceProvider)
          .trackWellInformedPromptSkipped(context: widget.context),
    );
    if (mounted) {
      ref.invalidate(wellInformedShouldShowProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return FadeTransition(
      opacity: _fadeCtrl,
      child: Container(
        margin: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space2,
          vertical: FacteurSpacing.space2,
        ),
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space4,
          FacteurSpacing.space4,
          FacteurSpacing.space2,
          FacteurSpacing.space4,
        ),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(FacteurRadius.large),
          border: Border.all(color: colors.border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    'À quel point te sens-tu bien informé·e en ce moment ?',
                    style: TextStyle(
                      color: colors.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                  ),
                ),
                const SizedBox(width: FacteurSpacing.space2),
                GestureDetector(
                  onTap: _handleSkip,
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      PhosphorIcons.x(),
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              '1 = pas / très mal · 10 = autant que je l\'aimerai, avec des informations de très bonne qualité',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                height: 1.4,
              ),
            ),
            const SizedBox(height: FacteurSpacing.space3),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (var i = 1; i <= 10; i++)
                  _ScorePill(
                    score: i,
                    enabled: !_submitting,
                    onTap: () => _handleSubmit(i),
                  ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space2),
            Text(
              'Cette réponse nous aide à mesurer si Facteur t\'aide à mieux t\'informer — et à comprendre ce qu\'il manquerait pour toujours mieux t\'y aider.',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 11,
                fontStyle: FontStyle.italic,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScorePill extends StatelessWidget {
  const _ScorePill({
    required this.score,
    required this.enabled,
    required this.onTap,
  });

  final int score;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Opacity(
      opacity: enabled ? 1.0 : 0.5,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: FacteurDurations.fast,
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: BorderRadius.circular(FacteurRadius.pill),
            border: Border.all(color: colors.border),
          ),
          child: Text(
            '$score',
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ),
    );
  }
}
