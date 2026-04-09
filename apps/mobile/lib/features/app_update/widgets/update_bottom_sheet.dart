import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../../../core/api/providers.dart';
import '../../../core/services/push_notification_service.dart';
import '../providers/app_update_provider.dart';
import '../services/app_update_service.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

enum _UpdateState { idle, downloading, downloaded, done, error, incompatible }

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
  String? _apkFilePath;
  bool _isDownloading = false;

  Future<void> _startDownload() async {
    if (_isDownloading) return;
    _isDownloading = true;

    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
      _errorMessage = null;
    });

    try {
      await PushNotificationService().showUpdateDownloadNotification();
    } catch (_) {
      // Notification failure is non-fatal
    }

    try {
      final apiClient = ref.read(apiClientProvider);
      final service = AppUpdateService(apiClient);

      final filePath = await service.downloadApk(
        onProgress: (received, total) {
          if (total > 0 && mounted) {
            setState(() => _progress = received / total);
          }
        },
      );

      if (mounted) {
        setState(() {
          _apkFilePath = filePath;
          _state = _UpdateState.downloaded;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('AppUpdate: download failed: $e');
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = 'Le téléchargement a échoué. Vérifiez votre connexion.';
        });
      }
    } finally {
      _isDownloading = false;
      try {
        await PushNotificationService().cancelUpdateDownloadNotification();
      } catch (_) {}
    }
  }

  Future<void> _triggerInstall() async {
    final path = _apkFilePath;
    if (path == null) return;

    try {
      final apiClient = ref.read(apiClientProvider);
      final service = AppUpdateService(apiClient);
      await service.installApk(path);

      if (mounted) {
        setState(() => _state = _UpdateState.done);
      }
    } on AppUpdateInstallException catch (e) {
      // ignore: avoid_print
      print('AppUpdate: install failed: $e');
      if (mounted) {
        setState(() {
          _state = e.isIncompatible
              ? _UpdateState.incompatible
              : _UpdateState.error;
          _errorMessage = e.message;
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('AppUpdate: install failed: $e');
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage = 'L\'installation a échoué. Réessayez.';
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
                'Mise à jour disponible',
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
            onPressed: _startDownload,
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
              'Téléchargement... ${(_progress * 100).toInt()}%',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              'Gardez l\'app ouverte pendant le téléchargement',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                    fontSize: 11,
                  ),
            ),
          ],
        );

      case _UpdateState.downloaded:
        return Column(
          children: [
            Row(
              children: [
                Icon(
                  PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                  color: colors.success,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Text(
                  'Téléchargement terminé',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.success,
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: _triggerInstall,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Installer maintenant'),
              ),
            ),
          ],
        );

      case _UpdateState.done:
        return Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.check_circle, color: colors.success, size: 20),
                const SizedBox(width: 8),
                Text(
                  'L\'installation a démarré',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.success,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Suivez les instructions sur votre écran',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textTertiary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => Navigator.of(context).pop(),
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Fermer'),
              ),
            ),
          ],
        );

      case _UpdateState.incompatible:
        return Column(
          children: [
            Icon(
              PhosphorIcons.warning(PhosphorIconsStyle.fill),
              color: colors.error,
              size: 32,
            ),
            const SizedBox(height: 12),
            Text(
              'Installation impossible',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: colors.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              'Cette mise à jour n\'est pas compatible avec la version installée.\n\n'
              'Désinstallez l\'app depuis les Paramètres Android, '
              'puis réinstallez-la depuis le lien de téléchargement.\n\n'
              'Vos données sont sauvegardées sur le serveur, rien ne sera perdu.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        );

      case _UpdateState.error:
        return Column(
          children: [
            Text(
              _errorMessage ?? 'Erreur lors du téléchargement',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.error,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _apkFilePath != null ? _triggerInstall : _startDownload,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(_apkFilePath != null ? 'Réessayer l\'installation' : 'Réessayer'),
              ),
            ),
          ],
        );
    }
  }
}
