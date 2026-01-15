import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

import 'package:webview_flutter_wkwebview/webview_flutter_wkwebview.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../config/theme.dart';
import '../../../core/api/api_client.dart';
import '../models/content_model.dart';
import '../repositories/feed_repository.dart';
import '../../../core/providers/analytics_provider.dart';
import 'perspectives_bottom_sheet.dart';

class ArticleViewerModal extends ConsumerStatefulWidget {
  final Content content;

  const ArticleViewerModal({super.key, required this.content});

  @override
  ConsumerState<ArticleViewerModal> createState() => _ArticleViewerModalState();
}

class _ArticleViewerModalState extends ConsumerState<ArticleViewerModal> {
  WebViewController? _controller;
  int _loadingProgress = 0;
  bool _hasError = false;
  bool _isSupported = true;
  late DateTime _startTime;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();

    // Check platform support
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      _isSupported = false;
      return;
    }

    try {
      // 1. Définir les paramètres de création selon la plateforme
      late final PlatformWebViewControllerCreationParams params;

      // On évite d'appeler WebViewPlatform.instance sur les plateformes desktop où il est souvent null
      // Sauf si on est sur iOS (WebKit) ou Android.
      if (!kIsWeb && Platform.isIOS) {
        params = WebKitWebViewControllerCreationParams(
          allowsInlineMediaPlayback: true,
        );
      } else {
        params = const PlatformWebViewControllerCreationParams();
      }

      // 2. Initialiser le controller
      _controller = WebViewController.fromPlatformCreationParams(params)
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setBackgroundColor(const Color(0x00000000))
        ..setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              if (mounted) {
                setState(() {
                  _loadingProgress = progress;
                });
              }
            },
            onPageStarted: (String url) {
              if (mounted) {
                setState(() {
                  _loadingProgress = 0;
                  _hasError = false;
                });
              }
            },
            onPageFinished: (String url) {
              if (mounted) {
                setState(() {
                  _loadingProgress = 100;
                });
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (mounted) {
                setState(() {
                  _hasError = true;
                });
              }
            },
          ),
        )
        ..loadRequest(Uri.parse(widget.content.url));
    } catch (e) {
      debugPrint('WebView initialization error: $e');
      _isSupported = false;
    }
  }

  @override
  void dispose() {
    // Track article read on close
    final duration = DateTime.now().difference(_startTime).inSeconds;
    // We use ref.read here because dispose is called when the widget is unmounted
    // but the provider container should still be alive.
    // However, if the whole app is closing, it might be too late.
    // For modal close, it's fine.
    ref
        .read(analyticsServiceProvider)
        .trackArticleRead(
          widget.content.id,
          widget.content.source.id,
          duration,
        );
    super.dispose();
  }

  Future<void> _showPerspectives(BuildContext context) async {
    // Show loading indicator
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        height: 200,
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Recherche de perspectives...'),
            ],
          ),
        ),
      ),
    );

    try {
      // Get the repository from provider
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);

      // Fetch perspectives
      final response = await repository.getPerspectives(widget.content.id);

      // Close loading dialog
      if (context.mounted) Navigator.pop(context);

      // Show perspectives bottom sheet
      if (context.mounted) {
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (ctx) => PerspectivesBottomSheet(
            perspectives: response.perspectives
                .map(
                  (PerspectiveData p) => Perspective(
                    title: p.title,
                    url: p.url,
                    sourceName: p.sourceName,
                    sourceDomain: p.sourceDomain,
                    biasStance: p.biasStance,
                    publishedAt: p.publishedAt,
                  ),
                )
                .toList(),
            biasDistribution: response.biasDistribution,
            keywords: response.keywords,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching perspectives: $e');
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Impossible de charger les perspectives'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      height: MediaQuery.of(context).size.height,
      decoration: BoxDecoration(color: colors.backgroundPrimary),
      child: Column(
        children: [
          // Handle & Header
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              children: [
                // Modal Handle
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textSecondary.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),
                // Header Content
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      // Close Button
                      IconButton(
                        icon: Icon(PhosphorIcons.x(PhosphorIconsStyle.bold)),
                        onPressed: () => Navigator.of(context).pop(),
                        color: colors.textPrimary,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),
                      // Source Info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    widget.content.source.name,
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (widget.content.source.biasStance !=
                                    'unknown') ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.textSecondary.withOpacity(
                                        0.08,
                                      ),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      widget.content.source.getBiasLabel(),
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                                if (widget.content.source.reliabilityScore !=
                                    'unknown') ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    widget.content.source.reliabilityScore ==
                                            'high'
                                        ? PhosphorIcons.sealCheck(
                                            PhosphorIconsStyle.fill,
                                          )
                                        : PhosphorIcons.warningCircle(
                                            PhosphorIconsStyle.fill,
                                          ),
                                    size: 13,
                                    color:
                                        widget
                                                .content
                                                .source
                                                .reliabilityScore ==
                                            'high'
                                        ? Colors.blue.shade300
                                        : Colors.amber.shade600,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Perspectives CTA
                      if (widget.content.contentType == ContentType.article)
                        TextButton(
                          onPressed: () => _showPerspectives(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 4,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: colors.primary.withOpacity(0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIcons.scales(PhosphorIconsStyle.fill),
                                size: 16,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                "Comparer",
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colors.primary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 4),
                      // Actions (Optional: Share/Save)
                      IconButton(
                        icon: Icon(
                          PhosphorIcons.shareNetwork(
                            PhosphorIconsStyle.regular,
                          ),
                        ),
                        onPressed: () {
                          // TODO: Implement share
                        },
                        color: colors.textPrimary,
                        visualDensity: VisualDensity.compact,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Progress Bar
          if (_loadingProgress < 100 && !_hasError)
            LinearProgressIndicator(
              value: _loadingProgress / 100.0,
              backgroundColor: colors.backgroundSecondary,
              color: colors.primary,
              minHeight: 2,
            )
          else
            const Divider(height: 1, thickness: 0.5),

          // WebView Content
          Expanded(
            child: Stack(
              children: [
                if (_isSupported && _controller != null)
                  WebViewWidget(controller: _controller!)
                else
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.monitor(PhosphorIconsStyle.duotone),
                            size: 64,
                            color: colors.textSecondary.withOpacity(0.5),
                          ),
                          const SizedBox(height: 24),
                          Text(
                            "WebView non supportée sur cette plateforme desktop",
                            textAlign: TextAlign.center,
                            style: textTheme.titleMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            "Le mode Modal WebView est optimisé pour Android et iOS. Sur desktop, nous recommandons l'ouverture dans votre navigateur.",
                            textAlign: TextAlign.center,
                            style: textTheme.bodyMedium?.copyWith(
                              color: colors.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 32),
                          ElevatedButton.icon(
                            onPressed: () =>
                                launchUrl(Uri.parse(widget.content.url)),
                            icon: Icon(
                              PhosphorIcons.browser(PhosphorIconsStyle.bold),
                            ),
                            label: const Text("Ouvrir dans le navigateur"),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (_hasError)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            PhosphorIcons.warningCircle(
                              PhosphorIconsStyle.duotone,
                            ),
                            size: 64,
                            color: colors.error,
                          ),
                          const SizedBox(height: 16),
                          Text(
                            "Erreur de chargement",
                            style: textTheme.titleMedium,
                          ),
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
                            onPressed: () => _controller?.reload(),
                            child: const Text("Réessayer"),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
