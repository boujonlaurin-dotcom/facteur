import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_downloader/flutter_downloader.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/api/providers.dart';
import '../providers/app_update_provider.dart';
import '../services/app_update_service.dart';

enum _UpdateState { idle, downloading, done, error, incompatible }

/// Bottom sheet showing update details and download progress.
///
/// The sheet is **non-dismissible by tap/drag** (faux-clic protection during
/// download). A close button is provided in safe states (idle/error/done).
class UpdateBottomSheet extends ConsumerStatefulWidget {
  final AppUpdateInfo info;

  const UpdateBottomSheet({super.key, required this.info});

  static Future<void> show(BuildContext context, {required AppUpdateInfo info}) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
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
  StreamSubscription<UpdateProgress>? _sub;

  @override
  void initState() {
    super.initState();
    _maybeResume();
  }

  Future<void> _maybeResume() async {
    final active = await AppUpdateService.instance.resumeIfActive();
    if (!mounted || active == null) return;
    _listen();
    _applyProgress(active);
  }

  void _listen() {
    _sub?.cancel();
    _sub = AppUpdateService.instance.progressStream.listen(_applyProgress);
  }

  void _applyProgress(UpdateProgress p) {
    if (!mounted) return;
    setState(() {
      switch (p.status) {
        case DownloadTaskStatus.enqueued:
        case DownloadTaskStatus.running:
        case DownloadTaskStatus.paused:
          _state = _UpdateState.downloading;
          _progress = (p.progress.clamp(0, 100)) / 100.0;
          break;
        case DownloadTaskStatus.complete:
          _state = _UpdateState.done;
          _progress = 1.0;
          // Auto-close after Android installer prompt opens.
          Future.delayed(const Duration(seconds: 2), () {
            if (mounted && _state == _UpdateState.done) {
              Navigator.of(context).maybePop();
            }
          });
          break;
        case DownloadTaskStatus.failed:
          _state = p.isIncompatible
              ? _UpdateState.incompatible
              : _UpdateState.error;
          _errorMessage = p.errorMessage ??
              'Le téléchargement a échoué. Vérifiez votre connexion.';
          break;
        case DownloadTaskStatus.canceled:
          _state = _UpdateState.error;
          _errorMessage = 'Téléchargement annulé.';
          break;
        case DownloadTaskStatus.undefined:
          break;
      }
    });
  }

  Future<void> _startUpdate() async {
    setState(() {
      _state = _UpdateState.downloading;
      _progress = 0;
    });
    _listen();

    try {
      final apiClient = ref.read(apiClientProvider);
      await AppUpdateService.instance.startUpdate(apiClient);
    } catch (e) {
      // ignore: avoid_print
      print('AppUpdate: download failed: $e');
      if (mounted) {
        setState(() {
          _state = _UpdateState.error;
          _errorMessage =
              'Le téléchargement a échoué. Vérifiez votre connexion.';
        });
      }
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  bool get _canClose =>
      _state != _UpdateState.downloading && _state != _UpdateState.done;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return PopScope(
      canPop: _canClose,
      child: Container(
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
                // Drag handle + close button row
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 8),
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: colors.textTertiary.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                      if (_canClose)
                        Align(
                          alignment: Alignment.centerRight,
                          child: IconButton(
                            icon: Icon(
                              Icons.close,
                              color: colors.textSecondary,
                              size: 22,
                            ),
                            onPressed: () => Navigator.of(context).maybePop(),
                            tooltip: 'Fermer',
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

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
      ),
    );
  }

  Widget _buildAndroidPermInfo(FacteurColors colors, {required bool compact}) {
    final text = compact
        ? 'Android peut vous demander d\'autoriser l\'installation à la fin du téléchargement — c\'est normal, cliquez sur Autoriser puis revenez ici.'
        : 'Android va vous demander d\'autoriser l\'installation depuis cette app. Cliquez sur Autoriser dans les paramètres qui s\'ouvrent — la mise à jour reprendra ensuite.';
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.primary.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            PhosphorIcons.info(PhosphorIconsStyle.fill),
            color: colors.primary,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionArea(BuildContext context, FacteurColors colors) {
    switch (_state) {
      case _UpdateState.idle:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildAndroidPermInfo(colors, compact: false),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _startUpdate,
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
          ],
        );

      case _UpdateState.downloading:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: _progress > 0 ? _progress : null,
                backgroundColor: colors.surface,
                valueColor: AlwaysStoppedAnimation(colors.primary),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _progress > 0
                  ? 'Téléchargement... ${(_progress * 100).toInt()}%'
                  : 'Téléchargement en cours...',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
            ),
            const SizedBox(height: 16),
            _buildAndroidPermInfo(colors, compact: true),
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
                onPressed: _startUpdate,
                style: OutlinedButton.styleFrom(
                  foregroundColor: colors.primary,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text('Réessayer'),
              ),
            ),
          ],
        );
    }
  }
}
