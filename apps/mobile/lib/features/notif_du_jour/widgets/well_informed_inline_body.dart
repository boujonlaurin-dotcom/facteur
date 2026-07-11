import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../well_informed/providers/well_informed_prompt_provider.dart';

/// Mini-form NPS du message « well_informed » de la Notif du jour : la rangée
/// de scores 1..10 remplace la zone CTA (`customBodyBuilder`). Submit → POST
/// + cooldown 14j (contrôleur existant) + consommation du message.
class WellInformedInlineBody extends ConsumerStatefulWidget {
  const WellInformedInlineBody({super.key, required this.consume});

  /// Replie la carte et consomme le message du jour.
  final Future<void> Function() consume;

  @override
  ConsumerState<WellInformedInlineBody> createState() =>
      _WellInformedInlineBodyState();
}

class _WellInformedInlineBodyState
    extends ConsumerState<WellInformedInlineBody> {
  bool _submitting = false;

  Future<void> _submit(int score) async {
    if (_submitting) return;
    setState(() => _submitting = true);
    unawaited(HapticFeedback.mediumImpact());
    final controller = ref.read(wellInformedPromptControllerProvider);
    await controller.submit(score, context: 'notif_du_jour');
    unawaited(
      ref.read(analyticsServiceProvider).trackWellInformedScoreSubmitted(
        score: score,
        context: 'notif_du_jour',
      ),
    );
    if (!mounted) return;
    ref.invalidate(wellInformedShouldShowProvider);
    await widget.consume();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(top: 5),
      child: Opacity(
        opacity: _submitting ? 0.5 : 1,
        child: Row(
          children: [
            for (var i = 1; i <= 10; i++) ...[
              if (i > 1) const SizedBox(width: 4),
              Expanded(
                child: GestureDetector(
                  onTap: _submitting ? null : () => _submit(i),
                  behavior: HitTestBehavior.opaque,
                  child: Container(
                    height: 24,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.border),
                    ),
                    child: Text(
                      '$i',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
