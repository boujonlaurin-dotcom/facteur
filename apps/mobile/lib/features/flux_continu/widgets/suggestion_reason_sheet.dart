import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';

/// Story 22.3 — sheet « Pourquoi cette section ? » d'une suggestion « Choisie
/// pour vous ». Transparence totale (PO) : le headline = la raison dominante,
/// les puces = le breakdown honnête servi par le backend (préférence déclarée /
/// lue + N articles + variété). Deux actions : garder (promotion en favori) ou
/// retirer (dismiss, mémoire locale). Pas d'em-dash dans la copy (règle PO).
Future<void> showSuggestionReasonSheet(
  BuildContext context, {
  required String sectionTitle,
  required SuggestionReason? reason,
  required Future<void> Function() onKeep,
  required Future<void> Function() onDismiss,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    enableDrag: true,
    isDismissible: true,
    barrierColor: Colors.black.withValues(alpha: 0.5),
    builder: (ctx) => ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: _SuggestionReasonContent(
          sectionTitle: sectionTitle,
          reason: reason,
          onKeep: onKeep,
          onDismiss: onDismiss,
        ),
      ),
    ),
  );
}

class _SuggestionReasonContent extends StatelessWidget {
  final String sectionTitle;
  final SuggestionReason? reason;
  final Future<void> Function() onKeep;
  final Future<void> Function() onDismiss;

  const _SuggestionReasonContent({
    required this.sectionTitle,
    required this.reason,
    required this.onKeep,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final bullets = reason?.breakdown ?? const <SuggestionContribution>[];

    return SafeArea(
      top: false,
      child: Container(
        decoration: BoxDecoration(
          color: colors.backgroundSecondary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle cosmétique + bouton fermer.
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: IconButton(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: Icon(Icons.close, color: colors.textTertiary),
                    tooltip: 'Fermer',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 36,
                      minHeight: 36,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: FacteurSpacing.space2),

            Row(
              children: [
                Icon(
                  PhosphorIcons.sparkle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Pourquoi cette section ?',
                    style: textTheme.displaySmall?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'Choisie pour vous dans « $sectionTitle », toujours à partir de '
              'tes préférences.',
              style: textTheme.bodySmall?.copyWith(
                color: colors.textTertiary,
                height: 1.4,
              ),
            ),

            if (reason != null && reason!.label.isNotEmpty) ...[
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                reason!.label,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ],

            const SizedBox(height: FacteurSpacing.space3),
            for (final c in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 5),
                      child: Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: colors.primary.withValues(alpha: 0.65),
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        c.label,
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textSecondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const SizedBox(height: FacteurSpacing.space4),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                  // Fire-and-forget : l'appelant (écran) attend et confirme.
                  onKeep();
                },
                icon: Icon(
                  PhosphorIcons.star(PhosphorIconsStyle.fill),
                  size: 16,
                ),
                label: const Text('Garder dans mes favoris'),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  backgroundColor: colors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(FacteurRadius.small),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: TextButton.icon(
                onPressed: () {
                  HapticFeedback.selectionClick();
                  Navigator.of(context).pop();
                  // Fire-and-forget : l'appelant (écran) attend et confirme.
                  onDismiss();
                },
                icon: Icon(
                  PhosphorIcons.minusCircle(PhosphorIconsStyle.regular),
                  size: 16,
                  color: colors.textSecondary,
                ),
                label: Text(
                  'Retirer cette suggestion',
                  style: TextStyle(color: colors.textSecondary),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
