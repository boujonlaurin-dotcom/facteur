import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../feed/models/content_model.dart';

import '../../gamification/widgets/streak_indicator.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import '../models/digest_mode.dart';
import '../providers/digest_mode_provider.dart';
import '../providers/digest_provider.dart';
import '../widgets/digest_briefing_section.dart';
import '../widgets/digest_personalization_sheet.dart';
import '../widgets/digest_welcome_modal.dart';

/// Main digest screen showing the daily "Essentiel" with 7 articles
/// Uses DigestBriefingSection with Feed-style header and segmented progress bar
class DigestScreen extends ConsumerStatefulWidget {
  const DigestScreen({super.key});

  @override
  ConsumerState<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends ConsumerState<DigestScreen> {
  bool _showWelcome = false;
  bool _hasCheckedWelcome = false;
  final ScrollController _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToTop() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        0,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void initState() {
    super.initState();
    // Note: _checkFirstTimeWelcome moved to didChangeDependencies()
    // because GoRouterState.of(context) requires mounted context
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // ignore: avoid_print
    print('DigestScreen: didChangeDependencies');

    // Robust check for first-time navigation parameter
    try {
      final state = GoRouterState.of(context);
      final isFirstStr = state.uri.queryParameters['first'];
      final isFirst = isFirstStr == 'true';

      // ignore: avoid_print
      print('DigestScreen: isFirst=$isFirst (raw: $isFirstStr)');

      if (isFirst && !_hasCheckedWelcome) {
        _hasCheckedWelcome = true; // Mark as checked to prevent re-triggering
        // Use post-frame callback to avoid showing modal during build
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _checkFirstTimeWelcome();
          }
        });
      }
    } catch (e) {
      // ignore: avoid_print
      print('DigestScreen: Error accessing GoRouterState: $e');
    }
  }

  Future<void> _checkFirstTimeWelcome() async {
    try {
      // Check for 'first' query param (from onboarding)
      final uri = GoRouterState.of(context).uri;
      final isFirstTime = uri.queryParameters['first'] == 'true';

      if (isFirstTime) {
        // Also check shared preferences to ensure we only show once
        final shouldShow = await DigestWelcomeModal.shouldShowWelcome();
        if (shouldShow && mounted) {
          setState(() {
            _showWelcome = true;
          });
        }
      }
    } catch (e, stack) {
      debugPrint('DigestScreen: Error in _checkFirstTimeWelcome: $e');
      debugPrint('Stack: $stack');
      // Silently ignore errors - welcome modal is not critical
    }
  }

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
    });
    // Clear the query param from URL
    context.go(RoutePaths.digest);
  }

  void _openArticle(DigestItem item) async {
    // Navigate to article detail first
    HapticFeedback.mediumImpact();
    final content = _convertToContent(item);
    await context.push('/feed/content/${item.contentId}', extra: content);

    // Mark as read when returning from article (only if not already read)
    if (!item.isRead && !item.isDismissed) {
      ref.read(digestProvider.notifier).applyAction(item.contentId, 'read');
    }
  }

  void _handleSave(DigestItem item) {
    HapticFeedback.lightImpact();
    ref.read(digestProvider.notifier).applyAction(
          item.contentId,
          item.isSaved ? 'unsave' : 'save',
        );
  }

  void _handleNotInterested(DigestItem item) {
    HapticFeedback.lightImpact();

    // Only open the personalization sheet — let user choose an action
    // (mute source, mute theme) from the modal. No immediate action.
    _showPersonalizationSheet(item);
  }

  void _showPersonalizationSheet(DigestItem item) {
    // Show DigestPersonalizationSheet with algorithm breakdown + mute options
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DigestPersonalizationSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('DigestScreen: build() called');
    final colors = context.facteurColors;
    final digestAsync = ref.watch(digestProvider);
    final modeState = ref.watch(digestModeProvider);

    // Initialiser le mode depuis la réponse API
    ref.listen(digestProvider, (previous, next) {
      next.whenData((digest) {
        if (digest != null && previous?.value?.mode != digest.mode) {
          ref.read(digestModeProvider.notifier).initFromDigestResponse(digest.mode);
        }
      });
    });

    // Listen to scroll to top trigger
    ref.listen(digestScrollTriggerProvider, (_, __) => _scrollToTop());

    debugPrint('DigestScreen: digestAsync state = ${digestAsync.toString()}');

    // Navigate to closure screen when digest is completed
    ref.listen(digestProvider, (previous, next) {
      next.whenData((digest) {
        if (digest != null &&
            digest.isCompleted &&
            previous?.value?.isCompleted != true) {
          // Navigate to closure screen on completion
          context.push('/digest/closure', extra: digest.digestId);
        }
      });
    });

    // Background color adapts to the current digest mode (both themes)
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modeBackgroundColor = isDark
        ? modeState.mode.backgroundColor
        : modeState.mode.lightBackgroundColor;
    final bgFadeTarget = isDark
        ? const Color(0xFF080808)
        : colors.backgroundPrimary;

    return Stack(
      children: [
        // Animated background layer for mode-based color shift
        AnimatedContainer(
          duration: const Duration(milliseconds: 600),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                modeBackgroundColor,
                Color.lerp(modeBackgroundColor, bgFadeTarget, 0.6)!,
              ],
            ),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: RefreshIndicator(
            onRefresh: () async {
              await ref.read(digestProvider.notifier).refreshDigest();
            },
            color: colors.primary,
            child: CustomScrollView(
              controller: _scrollController,
              slivers: [
                // Feed-style header with logo and streak
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(
                      horizontal: FacteurSpacing.space6,
                      vertical: FacteurSpacing.space4,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        StreakIndicator(),
                        FacteurLogo(size: 32),
                        // Empty space to balance layout
                        SizedBox(width: 48),
                      ],
                    ),
                  ),
                ),

                // Success banner when digest is completed
                SliverToBoxAdapter(
                  child: Builder(
                    builder: (context) {
                      // Check if completed using valueOrNull to avoid loading state issues
                      final digest = digestAsync.valueOrNull;
                      final isLoading = digestAsync.isLoading;

                      if (digest?.isCompleted == true) {
                        return Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 16,
                              ),
                              decoration: BoxDecoration(
                                color: colors.success.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(
                                  color: colors.success.withValues(alpha: 0.3),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    PhosphorIcons.checkCircle(
                                        PhosphorIconsStyle.fill),
                                    color: colors.success,
                                    size: 24,
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Briefing terminé !',
                                          style: TextStyle(
                                            color: colors.textPrimary,
                                            fontWeight: FontWeight.w700,
                                            fontSize: 16,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Revenez demain à 8h pour votre prochaine sélection.',
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                            fontWeight: FontWeight.w400,
                                            fontSize: 14,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            // Refresh button - top right (disabled during loading)
                            if (!isLoading)
                              Positioned(
                                top: 16,
                                right: 24,
                                child: Material(
                                  color: Colors.transparent,
                                  child: InkWell(
                                    onTap: () async {
                                      // Show confirmation dialog before regenerating
                                      final confirmed = await showDialog<bool>(
                                        context: context,
                                        builder: (context) => AlertDialog(
                                          title: const Text(
                                              'Générer un nouvel essentiel ?'),
                                          content: const Text(
                                            'Votre essentiel actuel sera remplacé par 5 nouveaux articles. Cette action est irréversible.',
                                          ),
                                          actions: [
                                            TextButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, false),
                                              child: const Text('Annuler'),
                                            ),
                                            FilledButton(
                                              onPressed: () =>
                                                  Navigator.pop(context, true),
                                              child: const Text('Confirmer'),
                                            ),
                                          ],
                                        ),
                                      );

                                      if (confirmed == true &&
                                          context.mounted) {
                                        final notifier =
                                            ref.read(digestProvider.notifier);
                                        notifier.forceRegenerate();
                                      }
                                    },
                                    borderRadius: BorderRadius.circular(16),
                                    child: Container(
                                      padding: const EdgeInsets.all(6),
                                      decoration: BoxDecoration(
                                        color: colors.textSecondary
                                            .withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(16),
                                      ),
                                      child: Icon(
                                        PhosphorIcons.arrowClockwise(
                                            PhosphorIconsStyle.bold),
                                        color: colors.textSecondary,
                                        size: 16,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        );
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),

                // Digest Briefing Section
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: digestAsync.when(
                      data: (digest) {
                        if (digest == null || digest.items.isEmpty) {
                          return _buildEmptyState(colors);
                        }

                        return Stack(
                          children: [
                            // Articles avec fade out/in animé pendant la régénération
                            AnimatedOpacity(
                              opacity: modeState.isRegenerating ? 0.15 : 1.0,
                              duration: const Duration(milliseconds: 300),
                              curve: Curves.easeOut,
                              child: IgnorePointer(
                                ignoring: modeState.isRegenerating,
                                child: DigestBriefingSection(
                                  items: digest.items,
                                  completionThreshold: digest.completionThreshold,
                                  onItemTap: _openArticle,
                                  onSave: _handleSave,
                                  onNotInterested: _handleNotInterested,
                                  mode: modeState.mode,
                                  isRegenerating: modeState.isRegenerating,
                                  onModeChanged: (mode) {
                                    ref.read(digestModeProvider.notifier).setMode(mode);
                                  },
                                ),
                              ),
                            ),
                            // Overlay de régénération avec shimmer
                            if (modeState.isRegenerating)
                              Positioned.fill(
                                child: _RegenerationOverlay(
                                  modeColor: modeState.mode.effectiveColor(colors.primary),
                                ),
                              ),
                          ],
                        );
                      },
                      loading: () => _buildLoadingState(colors),
                      error: (error, stack) =>
                          _buildErrorState(context, ref, colors, error),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        // Welcome modal overlay for first-time users
        if (_showWelcome)
          Positioned.fill(
            child: DigestWelcomeModal(
              onDismiss: _dismissWelcome,
            ),
          ),
      ],
    );
  }

  Widget _buildLoadingState(FacteurColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(
            color: colors.primary,
          ),
          const SizedBox(height: 16),
          Text(
            'Chargement de votre Essentiel...',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 16,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(FacteurColors colors) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.newspaper(),
            size: 64,
            color: colors.textTertiary,
          ),
          const SizedBox(height: 16),
          Text(
            'Aucun article aujourd\'hui',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Revenez plus tard pour découvrir votre Essentiel',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorState(
    BuildContext context,
    WidgetRef ref,
    FacteurColors colors,
    Object error,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            PhosphorIcons.warningCircle(),
            size: 64,
            color: colors.error,
          ),
          const SizedBox(height: 16),
          Text(
            'Erreur de chargement',
            style: TextStyle(
              color: colors.textSecondary,
              fontSize: 18,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            error.toString(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 14,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: () => ref.read(digestProvider.notifier).refreshDigest(),
            icon: Icon(PhosphorIcons.arrowClockwise()),
            label: const Text('Réessayer'),
          ),
        ],
      ),
    );
  }

  /// Converts DigestItem to Content for navigation and PersonalizationSheet
  Content _convertToContent(DigestItem item) {
    return Content(
      id: item.contentId,
      title: item.title,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      description: item.description,
      contentType: item.contentType,
      durationSeconds: item.durationSeconds,
      publishedAt: item.publishedAt ?? DateTime.now(),
      source: Source(
        id: item.source?.id ?? item.contentId,
        name: item.source?.name ?? 'Source inconnue',
        type: _mapSourceType(item.contentType),
        logoUrl: item.source?.logoUrl,
        theme: item.source?.theme,
      ),
    );
  }

  SourceType _mapSourceType(ContentType type) {
    switch (type) {
      case ContentType.video:
        return SourceType.video;
      case ContentType.audio:
        return SourceType.podcast;
      case ContentType.youtube:
        return SourceType.youtube;
      default:
        return SourceType.article;
    }
  }
}

/// Overlay de régénération avec animation de shimmer pulsé.
/// Affiché par-dessus les articles pendant que le backend régénère le digest.
class _RegenerationOverlay extends StatefulWidget {
  final Color modeColor;

  const _RegenerationOverlay({required this.modeColor});

  @override
  State<_RegenerationOverlay> createState() => _RegenerationOverlayState();
}

class _RegenerationOverlayState extends State<_RegenerationOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _pulseAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    )..repeat(reverse: true);
    _pulseAnimation = Tween<double>(begin: 0.3, end: 0.7).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulseAnimation,
      builder: (context, child) {
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(height: 120),
            // Icône animée avec pulse glow
            Container(
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: widget.modeColor.withValues(alpha: 0.12),
                boxShadow: [
                  BoxShadow(
                    color: widget.modeColor.withValues(
                      alpha: _pulseAnimation.value * 0.3,
                    ),
                    blurRadius: 24,
                    spreadRadius: 4,
                  ),
                ],
              ),
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: widget.modeColor.withValues(alpha: 0.8),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Recomposition en cours...',
              style: TextStyle(
                color: widget.modeColor.withValues(alpha: 0.8),
                fontSize: 14,
                fontWeight: FontWeight.w500,
                fontFamily: 'DM Sans',
              ),
            ),
          ],
        );
      },
    );
  }
}
