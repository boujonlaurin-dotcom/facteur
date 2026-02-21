import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/api/providers.dart';
import '../providers/app_update_provider.dart';
import '../services/app_update_service.dart';

enum _UpdateState { idle, downloading, done, error }

/// Bottom sheet showing update details and download progress.
class UpdateBottomSheet extends ConsumerStatefulWidget {
  final AppUpdateInfo info;

  const UpdateBottomSheet({super.key, required this.info});

  static Future<void> show(BuildContext context, {required AppUpdateInfo info}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => UpdateBottomSheet(info: info),
    );
  }

  @override
  ConsumerState<UpdateBottomSheet> createState() => _UpdateBottomSheetState();
}

class _UpdateBottomSheetState extends ConsumerState<UpdateBottomSheet> {
  _UpdateState _state = _UpdateState.idle;
  double _progress = 0;
  String? _errorMessage;

  Future<void> _startUpdate() async {
    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
    });

    try {
      final apiClient = ref.read(apiClientProvider);
      final service = AppUpdateService(apiClient);

      await service.downloadAndInstall(
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );

      if (mounted) {
        setState(() => _state = _UpdateState.done);
        // Close sheet after a short delay since Android installer is opening
        Future.delayed(const Duration(seconds: 1), () {
          if (mounted) Navigator.of(context).pop();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Container(
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 20),
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // Title
              Text(
                'Mise a jour disponible',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 4),

              // Release name
              Text(
                widget.info.name.isNotEmpty
                    ? widget.info.name
                    : widget.info.latestTag,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
              ),

              // APK size
              if (widget.info.apkSize != null) ...[
                const SizedBox(height: 2),
                Text(
                  widget.info.formattedSize,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                ),
              ],

              const SizedBox(height: 20),

              // Action area
              _buildActionArea(context, colors),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildActionArea(BuildContext context, FacteurColors colors) {
    switch (_state) {
      case _UpdateState.idle:
        return SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: _startUpdate,
            style: FilledButton.styleFrom(
              backgroundColor: colors.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Mettre a jour'),
          ),
        );

      case _UpdateState.downloading:
        return Column(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress,
                backgroundColor: colors.surface,
                valueColor: AlwaysStoppedAnimation(colors.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Telechargement... ${(_progress * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
          ],
        );

      case _UpdateState.done:
        return Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: colors.success, size: 20),
            const SizedBox(width: 8),
            Text(
              'Installation en cours...',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: colors.success,
                  ),
            ),
          ],
        );

      case _UpdateState.error:
        return Column(
          children: [
            Text(
              _errorMessage ?? 'Erreur lors du telechargement',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _startUpdate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Reessayer'),
              ),
            ),
          ],
        );
    }
  }
}
