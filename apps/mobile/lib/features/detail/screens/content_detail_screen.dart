import 'package:cached_network_image/cached_network_image.dart';
import 'package:facteur/core/utils/html_utils.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:url_launcher/url_launcher.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import '../../../config/theme.dart';
import '../../../core/api/api_client.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../feed/models/content_model.dart';
import '../../feed/repositories/feed_repository.dart';
import '../../feed/widgets/perspectives_bottom_sheet.dart';
import '../widgets/article_reader_widget.dart';
import '../widgets/audio_player_widget.dart';
import '../widgets/youtube_player_widget.dart';
import '../widgets/note_input_sheet.dart';
import '../widgets/note_welcome_tooltip.dart';
import '../../../core/ui/notification_service.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../../widgets/design/facteur_thumbnail.dart';

/// Écran de détail d'un contenu avec mode lecture In-App (Story 5.2)
/// Restauré avec les fonctionnalités de l'ancien ArticleViewerModal :
/// - Badge de biais politique
/// - Indicateur de fiabilité
/// - Bouton "Comparer" (perspectives)
/// - Analytics tracking
/// - Bookmark toggle
/// - Note sur article (Story Notes)
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
    with TickerProviderStateMixin {
  late AnimationController _fabController;
  late Animation<double> _fabAnimation;
  late AnimationController _buttonPulseController;
  late Animation<double> _buttonScaleAnimation;
  late AnimationController _bookmarkBounceController;
  late Animation<double> _bookmarkScaleAnimation;
  late AnimationController _noteFabBounceController;
  late Animation<double> _noteFabScaleAnimation;

  bool _showFab = false;
  bool _showNoteWelcome = false;
  late DateTime _startTime;
  WebViewController? _webViewController;
  bool _showWebView = false;

  Timer? _readingTimer;
  Timer? _noteNudgeTimer;
  bool _isConsumed = false;
  bool _hasOpenedNote = false;
  static const int _consumptionThreshold = 30; // seconds
  static const int _noteNudgeDelay = 20; // seconds

  Content? _content;

  @override
  void initState() {
    super.initState();
    _content = widget.content;
    _startTime = DateTime.now();
    if (_content != null) {
      _isConsumed = _content!.status == ContentStatus.consumed;
    }
    // Always fetch fresh content to accept latest metadata/status/theme
    _fetchContent();

    _fabController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _fabAnimation = CurvedAnimation(
      parent: _fabController,
      curve: Curves.easeOut,
    );

    // Pulse animation for the Compare button
    _buttonPulseController = AnimationController(
      duration: const Duration(milliseconds: 1000),
      vsync: this,
    );
    _buttonScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.05)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.05, end: 1.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 60,
      ),
    ]).animate(_buttonPulseController);

    // Bookmark bounce animation (triggered on first note character)
    _bookmarkBounceController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    _bookmarkScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 70,
      ),
    ]).animate(_bookmarkBounceController);

    // Note FAB bounce animation (triggered at +20s nudge)
    _noteFabBounceController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _noteFabScaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.2)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.2, end: 1.0)
            .chain(CurveTween(curve: Curves.bounceOut)),
        weight: 70,
      ),
    ]).animate(_noteFabBounceController);

    // Show FAB after a short delay for smooth appearance
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() => _showFab = true);
        _fabController.forward();
      }
    });

    // Check if note welcome tooltip should be shown (first time only)
    NoteWelcomeTooltip.shouldShow().then((show) {
      if (mounted && show) {
        setState(() => _showNoteWelcome = true);
      }
    });

    // Trigger button pulse after a delay to catch user's attention
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) {
        _buttonPulseController.forward();
      }
    });

    // Start timer if content is suitable for in-app reading and not already consumed
    if (_content?.hasInAppContent == true && !_isConsumed) {
      _startReadingTimer();
    }

    // Note nudge: bounce note FAB after 20s if user hasn't opened note
    _noteNudgeTimer = Timer(const Duration(seconds: _noteNudgeDelay), () {
      if (mounted && !_hasOpenedNote) {
        _noteFabBounceController.forward();
      }
    });
  }

  Future<void> _fetchContent() async {
    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      final content = await repository.getContent(widget.contentId);

      if (mounted) {
        if (content != null) {
          // Merge: preserve description/htmlContent from initial content
          // if the API response has less data (e.g. on-demand enrichment failed)
          // Guard against empty strings (not just null) to prevent losing initial data
          final merged = content.copyWith(
            description:
                (content.description != null && content.description!.isNotEmpty)
                    ? content.description
                    : _content?.description,
            htmlContent:
                (content.htmlContent != null && content.htmlContent!.isNotEmpty)
                    ? content.htmlContent
                    : _content?.htmlContent,
          );
          setState(() {
            _content = merged;
            _isConsumed = _content!.status == ContentStatus.consumed;
          });
          if (_content!.hasInAppContent == true && !_isConsumed) {
            _startReadingTimer();
          }
        } else {
          // Show error and pop if content not found
          NotificationService.showError('Contenu introuvable',
              context: context);
          context.pop();
        }
      }
    } catch (e) {
      debugPrint('Error fetching content: $e');
      if (mounted) {
        NotificationService.showError('Erreur de chargement', context: context);
        context.pop();
      }
    }
  }

  void _startReadingTimer() {
    _readingTimer?.cancel();
    _readingTimer = Timer(const Duration(seconds: _consumptionThreshold), () {
      if (mounted && !_isConsumed) {
        _markAsConsumed();
      }
    });
  }

  Future<void> _markAsConsumed() async {
    setState(() => _isConsumed = true);
    final content = _content;
    if (content == null) return;

    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.updateContentStatus(
        content.id,
        ContentStatus.consumed,
      );

      // Silent update - no notification needed as this is tracked automatically
    } catch (e) {
      debugPrint('Error marking as consumed: $e');
    }
  }

  Future<void> _toggleBookmark() async {
    final content = _content;
    if (content == null) return;

    HapticFeedback.lightImpact();
    final wasSaved = content.isSaved;
    final newSaved = !wasSaved;
    setState(() {
      _content = content.copyWith(isSaved: newSaved);
    });

    try {
      final supabase = Supabase.instance.client;
      final apiClient = ApiClient(supabase);
      final repository = FeedRepository(apiClient);
      await repository.toggleSave(content.id, newSaved);
      if (mounted && newSaved) {
        NotificationService.showInfo(
          'Sauvegardé',
          actionLabel: 'Ajouter à une collection',
          onAction: () => CollectionPickerSheet.show(context, content.id),
        );
      }
    } catch (e) {
      // Rollback on error
      if (mounted) {
        setState(() {
          _content = content.copyWith(isSaved: wasSaved);
        });
        NotificationService.showError('Erreur', context: context);
      }
    }
  }

  Future<void> _shareArticle() async {
    final content = _content;
    if (content == null) return;

    await Clipboard.setData(ClipboardData(text: content.url));
    if (mounted) {
      NotificationService.showInfo('Lien copié !');
    }
  }

  Future<void> _openNoteSheet() async {
    final content = _content;
    if (content == null) return;

    // Capture state before opening sheet
    final wasAlreadySaved = content.isSaved;
    final hadNote = content.hasNote;

    _hasOpenedNote = true;
    await NoteInputSheet.show(
      context,
      contentId: content.id,
      initialNoteText: content.noteText,
      onFirstCharacter: () {
        // Auto-bookmark (visual feedback deferred to sheet close)
        if (!content.isSaved) {
          setState(() {
            _content = content.copyWith(isSaved: true);
          });
        }
      },
      onNoteSaved: (text) {
        if (mounted) {
          setState(() {
            _content = _content?.copyWith(
              noteText: text,
              noteUpdatedAt: DateTime.now(),
              isSaved: true,
            );
          });
        }
      },
      onNoteDeleted: () {
        if (mounted) {
          setState(() {
            _content = _content?.clearNote();
          });
        }
      },
    );

    // Sheet closed — visual feedback if a note was created
    if (mounted && _content != null && _content!.hasNote && !hadNote) {
      _bookmarkBounceController.forward(from: 0);
      if (!wasAlreadySaved) {
        NotificationService.showInfo(
          'Sauvegardé',
          actionLabel: 'Ajouter à une collection',
          onAction: () => CollectionPickerSheet.show(context, _content!.id),
        );
      }
    }
  }

  @override
  void dispose() {
    _readingTimer?.cancel();
    _noteNudgeTimer?.cancel();
    _fabController.dispose();
    _buttonPulseController.dispose();
    _bookmarkBounceController.dispose();
    _noteFabBounceController.dispose();
    super.dispose();

    // Track article read duration on close (restored from ArticleViewerModal)
    try {
      if (_content != null) {
        final duration = DateTime.now().difference(_startTime).inSeconds;
        ref.read(analyticsServiceProvider).trackArticleRead(
              _content!.id,
              _content!.source.id,
              duration,
            );
      }
    } catch (e) {
      debugPrint('Error tracking analytics on dispose: $e');
    }
  }

  Future<void> _openOriginalUrl() async {
    final url = _content?.url;
    if (url != null) {
      final uri = Uri.tryParse(url);
      if (uri != null && await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  }

  String _getFabLabel() {
    switch (_content?.contentType) {
      case ContentType.youtube:
        return 'Ouvrir sur YouTube';
      case ContentType.audio:
        return 'Voir la source';
      default:
        return 'Voir l\'original';
    }
  }

  /// Show perspectives bottom sheet (restored from ArticleViewerModal)
  Future<void> _showPerspectives(BuildContext context) async {
    final content = _content;
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
        NotificationService.showError('Impossible de charger les perspectives',
            context: context);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    final content = _content;

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
    final useInAppReading = content.hasInAppContent && !_showWebView;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      body: Stack(
        children: [
          Builder(builder: (context) {
            final topInset = MediaQuery.of(context).padding.top;
            final headerHeight = topInset + 64;
            return Positioned.fill(
              child: Padding(
                padding: EdgeInsets.only(top: headerHeight),
                child: useInAppReading
                    ? _buildInAppContent(context, content)
                    : _buildWebViewFallback(content),
              ),
            );
          }),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildHeader(context, content),
          ),
        ],
      ),
      // FABs
      floatingActionButton: _showFab
          ? ScaleTransition(
              scale: _fabAnimation,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (_showNoteWelcome)
                    NoteWelcomeTooltip(
                      onDismiss: () => setState(() => _showNoteWelcome = false),
                    ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // External link FAB — hidden for articles unless WebView is shown
                      if (content.contentType != ContentType.article || _showWebView) ...[
                        FloatingActionButton(
                          mini: true,
                          onPressed: _openOriginalUrl,
                          backgroundColor:
                              colors.surface.withValues(alpha: 0.45),
                          foregroundColor: colors.textPrimary,
                          elevation: 2,
                          heroTag: 'original_fab',
                          tooltip: _getFabLabel(),
                          child: Icon(
                            PhosphorIcons.arrowSquareOut(
                                PhosphorIconsStyle.regular),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 8),
                      ],
                      // Note FAB (always primary, notes available on all articles)
                      ScaleTransition(
                        scale: _noteFabScaleAnimation,
                        child: FloatingActionButton(
                          mini: true,
                          onPressed: _openNoteSheet,
                          backgroundColor: colors.primary,
                          foregroundColor: Colors.white,
                          elevation: 4,
                          heroTag: 'note_fab',
                          tooltip: 'Nouvelle note',
                          child: Icon(
                            content.hasNote
                                ? PhosphorIcons.pencilLine(
                                    PhosphorIconsStyle.fill)
                                : PhosphorIcons.pencilLine(
                                    PhosphorIconsStyle.regular),
                            size: 20,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            )
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
    );
  }

  Widget _buildHeader(BuildContext context, Content content) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    // Wrap in SafeArea to respect Notch/StatusBar because we are in a Stack now
    return SafeArea(
      bottom: false,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space2,
          vertical: FacteurSpacing.space3,
        ),
        decoration: BoxDecoration(
          color: colors.backgroundPrimary,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: FacteurSpacing.space2),
              child: Row(
                children: [
                  // Discreet Back Button (reduced icon, maintained hitbox)
                  IconButton(
                    padding: const EdgeInsets.all(8),
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      PhosphorIcons.arrowLeft(PhosphorIconsStyle.regular),
                      size: 16,
                      color: colors.textSecondary,
                    ),
                    onPressed: () => context.pop(_content),
                  ),
                  const SizedBox(width: 4),

                  // Source logo (reduced from 32 to 28)
                  if (content.source.logoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: CachedNetworkImage(
                        imageUrl: content.source.logoUrl!,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) =>
                            _buildSourcePlaceholder(colors),
                      ),
                    )
                  else
                    _buildSourcePlaceholder(colors),
                  const SizedBox(width: 8),

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
                            // Bias dot
                            if (content.source.biasStance != 'unknown') ...[
                              const SizedBox(width: 6),
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: content.source.getBiasColor(),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 1),
                        // Ligne 2 : Temps relatif (icône + format court)
                        Row(
                          children: [
                            Icon(
                              PhosphorIcons.clock(PhosphorIconsStyle.regular),
                              size: 11,
                              color: colors.textTertiary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              timeago
                                  .format(content.publishedAt,
                                      locale: 'fr_short')
                                  .replaceAll('il y a ', ''),
                              style: textTheme.bodySmall?.copyWith(
                                color: colors.textTertiary,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),

                  // Share button — copie le lien dans le presse-papier
                  IconButton(
                    padding: const EdgeInsets.all(4),
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(),
                    onPressed: _shareArticle,
                    icon: Icon(
                      PhosphorIcons.shareNetwork(PhosphorIconsStyle.regular),
                      size: 22,
                      color: colors.textSecondary,
                    ),
                  ),

                  // Bookmark toggle (with bounce animation)
                  // Long-press opens collection picker
                  GestureDetector(
                    onLongPress: () {
                      HapticFeedback.mediumImpact();
                      CollectionPickerSheet.show(context, content.id);
                    },
                    child: ScaleTransition(
                      scale: _bookmarkScaleAnimation,
                      child: IconButton(
                        padding: const EdgeInsets.all(4),
                        visualDensity: VisualDensity.compact,
                        constraints: const BoxConstraints(),
                        onPressed: _toggleBookmark,
                        icon: Icon(
                          content.isSaved
                              ? PhosphorIcons.bookmarkSimple(
                                  PhosphorIconsStyle.fill)
                              : PhosphorIcons.bookmarkSimple(
                                  PhosphorIconsStyle.regular),
                          size: 22,
                          color: content.isSaved
                              ? colors.primary
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),

                  // Comparer button
                  if (content.contentType == ContentType.article) ...[
                    ScaleTransition(
                      scale: _buttonScaleAnimation,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(24),
                          boxShadow: [
                            BoxShadow(
                              color: colors.primary.withValues(alpha: 0.2),
                              blurRadius: 8,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: TextButton(
                          onPressed: () {
                            HapticFeedback.lightImpact();
                            _showPerspectives(context);
                          },
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
                            ),
                            minimumSize: const Size(0, 36),
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            backgroundColor: colors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(24),
                            ),
                            elevation: 0,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                PhosphorIcons.scales(PhosphorIconsStyle.fill),
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 8),
                              const Text(
                                'Comparer',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w900,
                                  color: Colors.white,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
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
    final topic = content.progressionTopic;

    if (topic != null) {
      // Logic for topic tracking can be added here if needed for analytics
      // but Footer CTA is removed per User Story 8 Refactor.
    }

    switch (content.contentType) {
      case ContentType.article:
        final colors = context.facteurColors;
        final textTheme = Theme.of(context).textTheme;
        final articleText = content.htmlContent ?? content.description;
        final isPartial = plainTextLength(articleText) < 500;

        String? readingTime;
        if (content.durationSeconds != null && content.durationSeconds! > 0) {
          final minutes = (content.durationSeconds! / 60).ceil();
          readingTime = '$minutes min de lecture';
        }

        return ArticleReaderWidget(
          htmlContent: content.htmlContent,
          description: content.description,
          title: content.title,
          header: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Hero thumbnail image (smooth integration)
              if (content.thumbnailUrl != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(FacteurRadius.large),
                  child: FacteurThumbnail(
                    imageUrl: content.thumbnailUrl,
                    aspectRatio: 16 / 9,
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space4),
              ],
              // "Aperçu" badge for partial content
              if (isPartial) ...[
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: colors.warning.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  ),
                  child: Text(
                    'Aperçu — contenu partiel',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.warning,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(height: FacteurSpacing.space3),
              ],
              // Title
              Text(
                content.title,
                style: textTheme.displayLarge?.copyWith(fontSize: 24),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              // Reading time
              if (readingTime != null) ...[
                Row(
                  children: [
                    Icon(
                      PhosphorIcons.timer(PhosphorIconsStyle.regular),
                      size: 14,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      readingTime,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: FacteurSpacing.space3),
              ],
              Divider(color: colors.border, height: 1),
              const SizedBox(height: FacteurSpacing.space4),
            ],
          ),
          footer: GestureDetector(
            onTap: () => setState(() => _showWebView = true),
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                borderRadius: BorderRadius.circular(FacteurRadius.large),
                border: Border.all(
                  color: colors.border.withValues(alpha: 0.5),
                ),
              ),
              child: Row(
                children: [
                  if (content.source.logoUrl != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: CachedNetworkImage(
                        imageUrl: content.source.logoUrl!,
                        width: 28,
                        height: 28,
                        fit: BoxFit.cover,
                        errorWidget: (_, __, ___) => Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: colors.surface,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Icon(
                            PhosphorIcons.newspaper(
                                PhosphorIconsStyle.regular),
                            size: 16,
                            color: colors.textTertiary,
                          ),
                        ),
                      ),
                    )
                  else
                    Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: colors.surface,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                        size: 16,
                        color: colors.textTertiary,
                      ),
                    ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Lire sur ${content.source.name}',
                      style: textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Icon(
                    PhosphorIcons.arrowRight(PhosphorIconsStyle.regular),
                    size: 20,
                    color: colors.textTertiary,
                  ),
                ],
              ),
            ),
          ),
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
