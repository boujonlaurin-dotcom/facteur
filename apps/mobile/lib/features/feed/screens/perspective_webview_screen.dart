import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';

import '../../../config/theme.dart';

/// Affiche une URL externe (typiquement un article d'une "autre source"
/// proposée dans la carte de comparaisons) dans une webview in-app, plutôt
/// que dans le navigateur système. Pousser cet écran via le **root navigator**
/// pour qu'il s'empile au-dessus de la bottom sheet de perspectives sans la
/// fermer ; un simple `Navigator.of(context).pop()` (ou swipe back iOS)
/// ramène l'utilisateur sur la sheet, intacte.
class PerspectiveWebViewScreen extends ConsumerStatefulWidget {
  final String url;
  final String sourceName;

  const PerspectiveWebViewScreen({
    super.key,
    required this.url,
    required this.sourceName,
  });

  @override
  ConsumerState<PerspectiveWebViewScreen> createState() =>
      _PerspectiveWebViewScreenState();
}

class _PerspectiveWebViewScreenState
    extends ConsumerState<PerspectiveWebViewScreen> {
  WebViewController? _controller;
  int _loadingProgress = 0;
  bool _hasError = false;
  bool _isSupported = true;

  @override
  void initState() {
    super.initState();

    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      _isSupported = false;
      return;
    }

    try {
      late final PlatformWebViewControllerCreationParams params;
      if (!kIsWeb && Platform.isIOS) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      _controller = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted && _loadingProgress != progress) {
                setState(() => _loadingProgress = progress);
              }
            },
            onPageStarted: (_) {
              if (mounted) {
                setState(() {
                  _loadingProgress = 0;
                  _hasError = false;
                });
              }
            },
            onPageFinished: (_) {
              if (mounted) setState(() => _loadingProgress = 100);
            },
            onWebResourceError: (_) {
              if (mounted) setState(() => _hasError = true);
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.url));
    } catch (e) {
      debugPrint('PerspectiveWebView init error: $e');
      _isSupported = false;
    }
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.tryParse(widget.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        elevation: 0,
        leading: IconButton(
          icon: Icon(
            PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
            color: colors.textPrimary,
          ),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text(
          widget.sourceName,
          style: textTheme.titleMedium?.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          IconButton(
            tooltip: 'Ouvrir dans le navigateur',
            icon: Icon(
              PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.regular),
              color: colors.textPrimary,
            ),
            onPressed: _openInBrowser,
          ),
        ],
      ),
      body: Column(
        children: [
          if (_loadingProgress < 100 && !_hasError && _isSupported)
            LinearProgressIndicator(
              value: _loadingProgress / 100.0,
              backgroundColor: colors.backgroundSecondary,
              color: colors.primary,
              minHeight: 2,
            )
          else
            Divider(
              height: 1,
              thickness: 0.5,
              color: colors.textTertiary.withValues(alpha: 0.3),
            ),
          Expanded(
            child: Stack(
              children: [
                if (_isSupported && _controller != null)
                  WebViewWidget(controller: _controller!)
                else
                  _UnsupportedView(onOpen: _openInBrowser),
                if (_hasError)
                  _ErrorView(
                    onRetry: () {
                      setState(() {
                        _hasError = false;
                        _loadingProgress = 0;
                      });
                      _controller?.reload();
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _UnsupportedView extends StatelessWidget {
  final VoidCallback onOpen;
  const _UnsupportedView({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              PhosphorIcons.monitor(PhosphorIconsStyle.duotone),
              size: 64,
              color: colors.textSecondary.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 24),
            Text(
              'WebView non supportée sur cette plateforme',
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onOpen,
              icon: Icon(PhosphorIcons.browser(PhosphorIconsStyle.bold)),
              label: const Text('Ouvrir dans le navigateur'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final VoidCallback onRetry;
  const _ErrorView({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    return Container(
      color: colors.backgroundPrimary,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.warningCircle(PhosphorIconsStyle.duotone),
                size: 64,
                color: colors.error,
              ),
              const SizedBox(height: 16),
              Text('Erreur de chargement', style: textTheme.titleMedium),
              const SizedBox(height: 8),
              Text(
                "Impossible de charger l'article. Vérifiez votre connexion ou réessayez plus tard.",
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                ),
                onPressed: onRetry,
                child: const Text('Réessayer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
