import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../providers/feed_provider.dart';
import '../providers/skip_provider.dart';
import '../../../core/ui/notification_service.dart';

class PersonalizationNudge extends ConsumerWidget {
  final String sourceId;
  final String sourceName;

  const PersonalizationNudge({
    super.key,
    required this.sourceId,
    required this.sourceName,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(PhosphorIcons.magicWand(PhosphorIconsStyle.duotone),
                  color: colors.primary, size: 20),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Personnalisation du flux',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Voir moins de "$sourceName" ?',
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 14,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              InkWell(
                onTap: () {
                  ref.read(skipProvider.notifier).clearSkip(sourceId);
                },
                borderRadius: BorderRadius.circular(20),
                child: Padding(
                  padding: const EdgeInsets.all(4.0),
                  child: Icon(PhosphorIcons.x(PhosphorIconsStyle.regular),
                      size: 18, color: colors.textTertiary),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () {
                  ref.read(skipProvider.notifier).clearSkip(sourceId);
                },
                style: TextButton.styleFrom(
                  foregroundColor: colors.textSecondary,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Annuler'),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () async {
                  ref.read(skipProvider.notifier).clearSkip(sourceId);

                  try {
                    // Use the new robust method based on ID
                    await ref
                        .read(feedProvider.notifier)
                        .muteSourceById(sourceId);
                    NotificationService.showInfo('Source masquée');
                  } catch (e) {
                    print('Error muting source: $e');
                    NotificationService.showError(
                        'Erreur: ${e.toString().replaceAll('Exception: ', '')}');
                  }
                },
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary.withValues(alpha: 0.1),
                  foregroundColor: colors.primary,
                  elevation: 0,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Masquer la source'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
