import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../config/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../feed/models/content_model.dart';
import '../../feed/repositories/feed_repository.dart';
import '../../feed/widgets/perspectives_bottom_sheet.dart';
import '../widgets/article_reader_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/youtube_player_widget.dart';

/// Écran de détail d'un contenu avec mode lecture In-App (Story 5.2)
/// Restauré avec les fonctionnalités de l'ancien ArticleViewerModal :
/// - Badge de biais politique
/// - Indicateur de fiabilité
/// - Bouton "Comparer" (perspectives)
/// - Analytics tracking
/// - Bookmark toggle
class ContentDetailScreen extends ConsumerStatefulWidget {
  final String contentId;
  final Content? content; // Passed via extra from GoRouter

  const ContentDetailScreen({
    super.key,
    required this.contentId,
    this.content,
  });

  @override
  ConsumerState<ContentDetailScreen> createState() =>
      _ContentDetailScreenState();
}

class _ContentDetailScreenState extends ConsumerState<ContentDetailScreen>
    with SingleTickerProviderStateMixin {
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;
  bool _showFab = false;
  bool _isSaved = false;
  late DateTime _startTime;
  WebViewController? _webViewController;

  @override
  void initState() {
    super.initState();
    _startTime = DateTime.now();
    _isSaved = widget.content?.isSaved ?? false;

    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOut,
    );

    // Show FAB after a short delay for smooth appearance
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _showFab = true);
        _fabController.forward();
      }
    });
  }

  @override
  void dispose() {
    // Track article read on close (restored from ArticleViewerModal)
    if (widget.content != null) {
      final duration = DateTime.now().difference(_startTime).inSeconds;
      ref.read(analyticsServiceProvider).trackArticleRead(
            widget.content!.id,
            widget.content!.source.id,
            duration,
          );
    }
    _fabController.dispose();
    super.dispose();
  }

  Future<void> _openOriginalUrl() async {
    final url = widget.content?.url;
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  String _getFabLabel() {
    switch (widget.content?.contentType) {
      case ContentType.youtube:
        return 'Ouvrir sur YouTube';
      case ContentType.audio:
        return 'Voir la source';
      default:
        return 'Voir l\'original';
    }
  }

  Future<void> _toggleBookmark() async {
    final content = widget.content;
    if (content == null) return;

    final previousState = _isSaved;
    setState(() => _isSaved = !_isSaved);

    try {
      // Call API to toggle saved state
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.toggleSave(content.id, _isSaved);
    } catch (e) {
      // Rollback on error
      debugPrint('Error toggling bookmark: $e');
      if (mounted) {
        setState(() => _isSaved = previousState);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Erreur lors de la sauvegarde'),
            duration: Duration(seconds: 2),
          ),
        );
      }
    }
  }

  /// Show perspectives bottom sheet (restored from ArticleViewerModal)
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
      // Get the repository from provider
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);

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
    final content = widget.content;

    // If no content passed, show loading or error
    if (content == null) {
      return Scaffold(
        backgroundColor: colors.backgroundPrimary,
        appBar: AppBar(
          backgroundColor: colors.backgroundPrimary,
          leading: IconButton(
            icon: Icon(
              PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
              color: colors.textPrimary,
            ),
            onPressed: () => context.pop(),
          ),
        ),
        body: Center(
          child: CircularProgressIndicator(color: colors.primary),
        ),
      );
    }

    // Determine if we should use in-app reading or fallback to WebView
    final useInAppReading = content.hasInAppContent;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: SafeArea(
        child: Column(
          children: [
            // Header
            _buildHeader(context, content),

            // Content area
            Expanded(
              child: useInAppReading
                  ? _buildInAppContent(context, content)
                  : _buildWebViewFallback(content),
            ),
          ],
        ),
      ),
      // FAB for opening original
      floatingActionButton: _showFab
          ? ScaleTransition(
              scale: _fabAnimation,
              child: FloatingActionButton.extended(
                onPressed: _openOriginalUrl,
                backgroundColor: colors.surface,
                foregroundColor: colors.textPrimary,
                elevation: 4,
                icon: Icon(
                  PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.regular),
                  size: 20,
                ),
                label: Text(
                  _getFabLabel(),
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildHeader(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top bar with back button, bookmark, and compare
          Row(
            children: [
              IconButton(
                icon: Icon(
                  PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                  color: colors.textPrimary,
                ),
                onPressed: () => context.pop(),
              ),
              const Spacer(),
              const Spacer(),

              // Bookmark toggle (functional now)
              IconButton(
                icon: Icon(
                  _isSaved
                      ? PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.fill)
                      : PhosphorIcons.bookmarkSimple(
                          PhosphorIconsStyle.regular),
                  color: _isSaved ? colors.primary : colors.textPrimary,
                ),
                onPressed: _toggleBookmark,
              ),
            ],
          ),

          const SizedBox(height: FacteurSpacing.space2),

          // Source info with bias badge and reliability indicator
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: FacteurSpacing.space2),
            child: Row(
              children: [
                // Source logo
                if (content.source.logoUrl != null)
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: CachedNetworkImage(
                      imageUrl: content.source.logoUrl!,
                      width: 32, // Slightly larger for better alignment
                      height: 32,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) =>
                          _buildSourcePlaceholder(colors),
                    ),
                  )
                else
                  _buildSourcePlaceholder(colors),
                const SizedBox(width: 10),

                // Source Name + Time + Badges
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Ligne 1 : Nom + Badges
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              content.source.name,
                              style: textTheme.labelMedium?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: colors.textPrimary,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          // Bias badge
                          if (content.source.biasStance != 'unknown') ...[
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
                                content.source.getBiasLabel(),
                                style: TextStyle(
                                  fontSize: 9,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ),
                          ],
                          // Reliability indicator
                          if (content.source.reliabilityScore != 'unknown') ...[
                            const SizedBox(width: 4),
                            Icon(
                              content.source.reliabilityScore == 'high'
                                  ? PhosphorIcons.sealCheck(
                                      PhosphorIconsStyle.fill)
                                  : PhosphorIcons.warningCircle(
                                      PhosphorIconsStyle.fill),
                              size: 13,
                              color: content.source.reliabilityScore == 'high'
                                  ? Colors.blue.shade300
                                  : Colors.amber.shade600,
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      // Ligne 2 : Temps relatif
                      Text(
                        timeago.format(content.publishedAt, locale: 'fr'),
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textTertiary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),

                // Comparer button (Moved here)
                if (content.contentType == ContentType.article) ...[
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: () => _showPerspectives(context),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8, // Taller touch target
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      backgroundColor: colors.primary.withOpacity(0.18),
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
                          PhosphorIcons.scales(PhosphorIconsStyle.fill),
                          size: 16,
                          color: colors.primary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Comparer',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: colors.primary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ],
            ),
          ),

          const SizedBox(height: FacteurSpacing.space4),

          // Title
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: FacteurSpacing.space2),
            child: Text(
              content.title,
              style: textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),

          const SizedBox(height: FacteurSpacing.space2),
        ],
      ),
    );
  }

  Widget _buildSourcePlaceholder(FacteurColors colors) {
    return Container(
      width: 24,
      height: 24,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(
        PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
        size: 14,
        color: colors.textTertiary,
      ),
    );
  }

  Widget _buildInAppContent(BuildContext context, Content content) {
    switch (content.contentType) {
      case ContentType.article:
        return ArticleReaderWidget(
          htmlContent: content.htmlContent,
          description: content.description,
          title: content.title,
        );

      case ContentType.audio:
        return AudioPlayerWidget(
          audioUrl: content.audioUrl!,
          title: content.title,
          description: content.description,
          thumbnailUrl: content.thumbnailUrl,
          durationSeconds: content.durationSeconds,
        );

      case ContentType.youtube:
      case ContentType.video:
        return YouTubePlayerWidget(
          videoUrl: content.url,
          title: content.title,
          description: content.description,
        );
    }
  }

  Widget _buildWebViewFallback(Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // WebView not supported on web platform - show fallback UI
    if (kIsWeb) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(FacteurSpacing.space6),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                PhosphorIcons.globe(PhosphorIconsStyle.duotone),
                size: 64,
                color: colors.textTertiary,
              ),
              const SizedBox(height: FacteurSpacing.space4),
              Text(
                'Contenu non disponible en aperçu',
                style: textTheme.titleMedium?.copyWith(
                  color: colors.textPrimary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                'Cliquez sur le bouton ci-dessous pour lire l\'article original.',
                style: textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: FacteurSpacing.space6),
              ElevatedButton.icon(
                onPressed: _openOriginalUrl,
                icon: Icon(
                    PhosphorIcons.arrowSquareOut(PhosphorIconsStyle.regular)),
                label: const Text('Ouvrir l\'article'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: colors.primary,
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      );
    }

    // Mobile: Use native WebView
    _webViewController ??= WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..loadRequest(Uri.parse(content.url));

    return WebViewWidget(controller: _webViewController!);
  }
}
