import 'dart:io';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/app_update_provider.dart';
import 'update_bottom_sheet.dart';

/// Key used in Hive 'settings' box to persist dismiss timestamp.
const _kDismissedAtKey = 'update_modal_dismissed_at';

/// Cooldown duration before re-showing the modal after dismiss.
const _kDismissCooldown = Duration(days: 5);

/// Modal dialog shown at app launch when an update is available.
///
/// Two actions:
/// - "Mettre à jour" → opens the download bottom sheet
/// - "Me le rappeler plus tard" → dismisses for 5 days
class UpdateModal {
  UpdateModal._();

  /// Returns true if the modal should be shown (not dismissed recently).
  static bool shouldShow() {
    if (kIsWeb || !Platform.isAndroid) return false;

    final box = Hive.box<dynamic>('settings');
    final dismissedAt = box.get(_kDismissedAtKey) as int?;
    if (dismissedAt == null) return true;

    final elapsed = DateTime.now().millisecondsSinceEpoch - dismissedAt;
    return elapsed >= _kDismissCooldown.inMilliseconds;
  }

  /// Persists the dismiss timestamp so the modal won't reappear for 5 days.
  static void _persistDismiss() {
    final box = Hive.box<dynamic>('settings');
    box.put(_kDismissedAtKey, DateTime.now().millisecondsSinceEpoch);
  }

  /// Shows the update modal dialog. Call only after confirming [shouldShow]
  /// and that [info.updateAvailable] is true.
  static Future<void> show(BuildContext context, {required AppUpdateInfo info}) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _UpdateModalDialog(info: info),
    );
  }
}

class _UpdateModalDialog extends StatelessWidget {
  final AppUpdateInfo info;

  const _UpdateModalDialog({required this.info});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Dialog(
      backgroundColor: colors.backgroundSecondary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Icon
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: colors.primary.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                PhosphorIcons.arrowCircleDown(PhosphorIconsStyle.fill),
                color: colors.primary,
                size: 28,
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Mise à jour disponible',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),

            // Subtitle with version
            Text(
              info.name.isNotEmpty ? info.name : info.latestTag,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),

            if (info.apkSize != null) ...[
              const SizedBox(height: 4),
              Text(
                info.formattedSize,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
              ),
            ],

            const SizedBox(height: 24),

            // "Mettre à jour" button
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  UpdateBottomSheet.show(context, info: info);
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Mettre à jour'),
              ),
            ),
            const SizedBox(height: 10),

            // "Me le rappeler plus tard" button
            SizedBox(
              width: double.infinity,
              child: TextButton(
                onPressed: () {
                  UpdateModal._persistDismiss();
                  Navigator.of(context).pop();
                },
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Me le rappeler plus tard'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
