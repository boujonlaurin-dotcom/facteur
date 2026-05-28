import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:io';
import 'package:flutter/foundation.dart';

import '../../../config/theme.dart';
import '../models/content_model.dart';
import '../providers/feed_provider.dart';
import '../repositories/feed_repository.dart';
import '../../../core/providers/analytics_provider.dart';
import 'perspectives_bottom_sheet.dart';
import '../../../core/ui/notification_service.dart';

class ArticleViewerModal extends ConsumerStatefulWidget {
  final Content? content;

  /// URL chargée dans la webview. Si [content] est fourni, on utilise son URL ;
  /// sinon (mode "perspective") on charge directement cette URL.
  final String? url;

  /// Nom de la source affiché dans le header en mode perspective.
  final String? sourceName;

  /// Domaine source — utile pour fallback favicon / source detail.
  final String? sourceDomain;

  /// Bias stance en mode perspective ('left', 'center-left', 'center',
  /// 'center-right', 'right', 'unknown').
  final String? biasStance;

  const ArticleViewerModal({super.key, required Content this.content})
      : url = null,
        sourceName = null,
        sourceDomain = null,
        biasStance = null;

  /// Mode "perspective" : la modal ouvre une URL externe (autre source) avec
  /// le même header / webview que pour un article interne. Pas de tracking
  /// `trackArticleRead` ni d'update de `user_content_status` (l'event
  /// `perspective_article_viewed` est déjà émis par
  /// `PerspectivesBottomSheet` au tap). Bouton "Comparer" masqué — on est
  /// déjà dans une sheet de comparaisons.
  const ArticleViewerModal.perspective({
    super.key,
    required String this.url,
    required String this.sourceName,
    this.sourceDomain,
    String this.biasStance = 'unknown',
  }) : content = null;

  @override
  ConsumerState<ArticleViewerModal> createState() => _ArticleViewerModalState();
}

class _ArticleViewerModalState extends ConsumerState<ArticleViewerModal> {
  WebViewController? _controller;
  int _loadingProgress = 0;
  bool _hasError = false;
  bool _isSupported = true;
  late DateTime _startTime;

  String get _url => widget.content?.url ?? widget.url!;


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
      // Bare WebViewController() — pattern identique à
      // `ContentDetailScreen._initScrollToSiteWebView()`. On évite les
      // `WebKitWebViewControllerCreationParams` qui faisaient apparaître des
      // redirects Google login sur certains domaines.
      _controller = WebViewController()
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
        ..loadRequest(Uri.parse(_url));
    } catch (e) {
      debugPrint('WebView initialization error: $e');
      _isSupported = false;
    }
  }

  @override
  void dispose() {
    final content = widget.content;
    if (content != null) {
      final duration = DateTime.now().difference(_startTime).inSeconds;
      // Le ProviderScope peut être disposé avant ce widget en tests / teardown.
      try {
        ref.read(analyticsServiceProvider).trackArticleRead(
              content.id,
              content.source.id,
              duration,
            );
        ref
            .read(feedRepositoryProvider)
            .updateContentStatusWithTimeSpent(content.id, duration);
      } catch (e) {
        debugPrint('[ArticleViewerModal] dispose tracking error: $e');
      }
    }
    super.dispose();
  }

  Future<void> _showPerspectives(BuildContext context) async {
    final content = widget.content;
    if (content == null) return;

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
      final repository = ref.read(feedRepositoryProvider);

      // Fetch perspectives
      final response = await repository.getPerspectives(content.id);

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
                    highlightSpans: p.highlightSpans,
                    sharedTokens: p.sharedTokens,
                  ),
                )
                .toList(),
            biasDistribution: response.biasDistribution,
            keywords: response.keywords,
            sourceBiasStance: response.sourceBiasStance,
            sourceName: content.source.name,
            contentId: content.id,
            comparisonQuality: response.comparisonQuality,
          ),
        );
      }
    } catch (e) {
      debugPrint('Error fetching perspectives: $e');
      if (context.mounted) Navigator.pop(context);
      if (context.mounted) {
        NotificationService.showError('Impossible de charger les perspectives');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final content = widget.content;
    final displaySourceName =
        content?.source.name ?? widget.sourceName ?? '';
    final displayBiasStance =
        content?.source.biasStance ?? widget.biasStance ?? 'unknown';
    final displayBiasLabel =
        content?.source.getBiasLabel() ?? Perspective.getBiasLabelFromStance(displayBiasStance);
    final displayReliability =
        content?.source.reliabilityScore ?? 'unknown';

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
                                    displaySourceName,
                                    style: textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: colors.textPrimary,
                                      fontSize: 13,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (displayBiasStance != 'unknown') ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: colors.textSecondary.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      displayBiasLabel,
                                      style: TextStyle(
                                        fontSize: 9,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ),
                                ],
                                if (displayReliability != 'unknown') ...[
                                  const SizedBox(width: 4),
                                  Icon(
                                    displayReliability == 'high'
                                        ? PhosphorIcons.sealCheck(
                                            PhosphorIconsStyle.fill,
                                          )
                                        : PhosphorIcons.warningCircle(
                                            PhosphorIconsStyle.fill,
                                          ),
                                    size: 13,
                                    color: displayReliability == 'high'
                                        ? Colors.blue.shade300
                                        : Colors.amber.shade600,
                                  ),
                                ],
                              ],
                            ),
                          ],
                        ),
                      ),
                      // Share Button
                      IconButton(
                        icon: Icon(PhosphorIcons.shareNetwork(
                            PhosphorIconsStyle.bold)),
                        onPressed: () async {
                          await Clipboard.setData(
                              ClipboardData(text: _url));
                          if (context.mounted) {
                            NotificationService.showInfo('Lien copié !');
                          }
                        },
                        color: colors.textPrimary,
                        visualDensity: VisualDensity.compact,
                      ),
                      const SizedBox(width: 8),

                      // Perspectives CTA — caché en mode perspective (on est
                      // déjà dans une sheet de comparaisons).
                      if (content != null &&
                          content.contentType == ContentType.article)
                        TextButton(
                          onPressed: () => _showPerspectives(context),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor:
                                colors.primary.withOpacity(0.18),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: colors.primary.withOpacity(0.4),
                                width: 1.2,
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIcons.eye(PhosphorIconsStyle.fill),
                                size: 18,
                                color: colors.primary,
                              ),
                              const SizedBox(width: 5),
                              Text(
                                'Comparer',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                  color: colors.primary,
                                  letterSpacing: 0.2,
                                ),
                              ),
                            ],
                          ),
                        ),
                      const SizedBox(width: 4),
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
                            'WebView non supportée sur cette plateforme desktop',
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
                            onPressed: () => launchUrl(Uri.parse(_url)),
                            icon: Icon(
                              PhosphorIcons.browser(PhosphorIconsStyle.bold),
                            ),
                            label: const Text('Ouvrir dans le navigateur'),
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
                            'Erreur de chargement',
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
                            child: const Text('Réessayer'),
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
