import 'dart:io';

import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/nudge_service.dart';
import '../../../core/services/widget_service.dart';

/// Bottom sheet nudging the user to pin the Facteur widget on their home screen.
///
/// Shown once after onboarding (Android only). Uses SharedPreferences
/// to track whether the nudge has already been displayed.
class WidgetPinNudge {
  /// Returns true if the nudge should be shown (Android + never shown before).
  static Future<bool> shouldShow() async {
    if (!Platform.isAndroid) return false;
    return NudgeService().canShow(NudgeIds.widgetPinAndroid);
  }

  /// Mark the nudge as shown so it won't appear again.
  static Future<void> markShown() =>
      NudgeService().markSeen(NudgeIds.widgetPinAndroid);

  /// Show the bottom sheet. Call after welcome modal dismissal.
  static Future<void> show(BuildContext context) async {
    final shouldDisplay = await shouldShow();
    if (!shouldDisplay || !context.mounted) return;

    await markShown();

    if (!context.mounted) return;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => const _WidgetPinSheet(),
    );
  }
}

class _WidgetPinSheet extends StatelessWidget {
  const _WidgetPinSheet();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(FacteurRadius.large),
        ),
      ),
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: colors.textTertiary.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),

          // Icon
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colors.primary.withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              PhosphorIcons.squaresFour(PhosphorIconsStyle.fill),
              color: colors.primary,
              size: 28,
            ),
          ),

          const SizedBox(height: 16),

          // Title
          Text(
            'Ajouter le widget Facteur ?',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 8),

          // Description
          Text(
            'Retrouve ton essentiel du jour directement sur ton écran d\'accueil, sans ouvrir l\'app.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: 24),

          // CTA button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await WidgetService.requestPinWidget();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                backgroundColor: colors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(FacteurRadius.large),
                ),
              ),
              child: const Text(
                'Ajouter le widget',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),

          const SizedBox(height: 12),

          // Skip
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              'Plus tard',
              style: TextStyle(
                color: colors.textTertiary,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
