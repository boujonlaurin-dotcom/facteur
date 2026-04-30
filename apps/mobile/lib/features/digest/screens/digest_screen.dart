import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../shared/widgets/loaders/loading_view.dart';
import '../../../shared/widgets/mode_accent.dart';
import '../../../shared/widgets/states/friendly_error_view.dart';
import '../../../shared/widgets/states/laurin_fallback_view.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../feed/models/content_model.dart';

import '../../feed/providers/feed_provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart';
import '../models/community_carousel_model.dart';
import '../models/digest_models.dart';
import '../providers/digest_format_provider.dart';
import '../providers/community_carousel_provider.dart';
import '../providers/digest_provider.dart';
import '../providers/serein_toggle_provider.dart';
import '../../../core/services/widget_service.dart';
import '../widgets/digest_briefing_section.dart';
import '../widgets/digest_hero.dart';
import '../widgets/digest_personalization_sheet.dart';
import '../widgets/widget_pin_nudge.dart';
import 'closure_screen.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../saved/providers/collections_provider.dart';
import '../../../core/ui/notification_service.dart';

/// Main digest screen showing the daily "Essentiel" with 7 articles
/// Uses DigestBriefingSection with Feed-style header and segmented progress bar
class DigestScreen extends ConsumerStatefulWidget {
  const DigestScreen({super.key});

  @override
  ConsumerState<DigestScreen> createState() => _DigestScreenState();
}

class _DigestScreenState extends ConsumerState<DigestScreen> {
  int _consecutiveErrorCount = 0;
  final ScrollController _scrollController = ScrollController();
  // Sprint 2 PR1 — dedupe digest_opened + digest_item_viewed per digest_id.
  String? _trackedDigestId;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetService.initWidgetIfNeeded();
    // Nudge to pin the Android widget once after first display.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        WidgetPinNudge.show(context, ref);
      }
    });
  }

  /// Show the closure screen as a modal (slides up from bottom) instead of
  /// pushing a route, so the digest stays in place behind it.
  void _showClosureModal(String digestId) {
    showGeneralDialog<void>(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer',
      barrierColor: Colors.black.withOpacity(0.35),
      transitionDuration: const Duration(milliseconds: 320),
      pageBuilder: (_, __, ___) => ClosureScreen(digestId: digestId),
      transitionBuilder: (_, animation, __, child) {
        final curved =
            CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 1),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        );
      },
    );
  }

  void _openArticle(DigestItem item) async {
    HapticFeedback.mediumImpact();

    // Mark as read on tap, before navigation — gives immediate feedback on
    // the progress micro-bars without waiting for the user to pop back.
    if (!item.isRead && !item.isDismissed) {
      ref.read(digestProvider.notifier).applyAction(item.contentId, 'read');
    }

    // Premium source → open in external browser for authenticated access
    final sources = ref.read(userSourcesProvider).valueOrNull ?? [];
    final isPremium = item.source?.id != null &&
        sources.any((s) => s.id == item.source!.id && s.hasSubscription);
    if (isPremium && item.url.isNotEmpty) {
      final uri = Uri.tryParse(item.url);
      if (uri != null) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    // Navigate to article detail
    final content = _convertToContent(item);
    final updated = await context
        .push<Content?>('/feed/content/${item.contentId}', extra: content);

    // Sync bookmark + note state back to digest
    if (updated != null) {
      if (updated.isSaved != item.isSaved ||
          updated.noteText != item.noteText) {
        ref.read(digestProvider.notifier).syncItemFromDetail(
              item.contentId,
              isSaved: updated.isSaved,
              noteText: updated.noteText,
            );
      }
    }
  }

  /// Filter the digest community carousel to exclude any article that already
  /// appears in the main digest flow (flat items + per-topic articles). The
  /// backend deduplicates Feed↔Digest carousels, but a digest article picked
  /// for the carousel would still look duplicated to the user.
  List<CommunityCarouselItem> _filterCommunityCarousel(DigestResponse digest) {
    final all = ref.watch(communityCarouselProvider).valueOrNull?.digestCarousel;
    if (all == null || all.isEmpty) return const [];
    final shownIds = <String>{
      for (final it in digest.items) it.contentId,
      for (final t in digest.topics)
        for (final it in t.articles) it.contentId,
    };
    return all.where((ci) => !shownIds.contains(ci.contentId)).toList();
  }

  void _handleLike(DigestItem item) {
    HapticFeedback.mediumImpact();
    ref.read(digestProvider.notifier).applyAction(
          item.contentId,
          item.isLiked ? 'unlike' : 'like',
        );
    NotificationService.showInfo(
      item.isLiked
          ? 'Retiré de Mes contenus recommandés 🌻'
          : 'Ajouté à Mes contenus recommandés 🌻',
    );
    ref.invalidate(collectionsProvider);
  }

  void _handleSave(DigestItem item) async {
    final wasSaved = item.isSaved;
    HapticFeedback.lightImpact();
    ref.read(digestProvider.notifier).applyAction(
          item.contentId,
          wasSaved ? 'unsave' : 'save',
        );
    if (!wasSaved) {
      // Auto-add to default collection
      final defaultCol = ref.read(defaultCollectionProvider);
      if (defaultCol != null) {
        final colRepo = ref.read(collectionsRepositoryProvider);
        await colRepo.addToCollection(defaultCol.id, item.contentId);
        ref.invalidate(collectionsProvider);
      }
      if (mounted) {
        CollectionPickerSheet.show(context, item.contentId);
      }
    }
  }

  void _handleReportNotSerene(DigestItem item) {
    ref.read(digestProvider.notifier).applyAction(
          item.contentId,
          'report_not_serene',
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

  void _handleSwipeDismiss(DigestItem item) {
    HapticFeedback.lightImpact();
    ref
        .read(digestProvider.notifier)
        .applyAction(item.contentId, 'not_interested');
  }

  @override
  Widget build(BuildContext context) {
    debugPrint('DigestScreen: build() called');
    final colors = context.facteurColors;
    final digestAsync = ref.watch(digestProvider);
    final sereinState = ref.watch(sereinToggleProvider);

    // Initialiser le format depuis la réponse API
    ref.listen(digestProvider, (previous, next) {
      next.whenData((digest) {
        if (digest != null &&
            previous?.value?.formatVersion != digest.formatVersion) {
          ref
              .read(digestFormatProvider.notifier)
              .initFromDigestResponse(digest.formatVersion);
        }
      });
    });

    // Sprint 2 PR1 — fire digest_opened + digest_item_viewed once per digest.
    // Semantics: "items rendered in the list" — digest is short (≤ 7 items
    // typically) so presentation ≈ visibility without per-card VisibilityDetector
    // wiring across the editorial/ranked/topics layouts.
    ref.listen(digestProvider, (previous, next) {
      next.whenData((digest) {
        if (digest == null) return;
        if (_trackedDigestId == digest.digestId) return;
        _trackedDigestId = digest.digestId;
        final analytics = ref.read(analyticsServiceProvider);
        final dateIso = digest.targetDate.toIso8601String().substring(0, 10);
        unawaited(
          analytics.trackDigestOpened(
            digestDate: dateIso,
            itemsCount: digest.items.length,
          ),
        );
        for (var i = 0; i < digest.items.length; i++) {
          final item = digest.items[i];
          unawaited(
            analytics.trackDigestItemViewed(
              digestDate: dateIso,
              contentId: item.contentId,
              position: i,
            ),
          );
        }
      });
    });

    // Compteur d'échecs consécutifs (alimente FriendlyErrorView vs
    // LaurinFallbackView). Reset sur succès, incrément à chaque transition
    // vers un état d'erreur.
    ref.listen(digestProvider, (previous, next) {
      if (next is AsyncError && previous is! AsyncError) {
        if (mounted) {
          setState(() => _consecutiveErrorCount++);
        }
      } else if (next is AsyncData && _consecutiveErrorCount != 0) {
        if (mounted) {
          setState(() => _consecutiveErrorCount = 0);
        }
      }
    });

    debugPrint('DigestScreen: digestAsync state = ${digestAsync.toString()}');

    // Open closure modal when digest completes. Rendered as a modal (not a
    // route push) so the digest screen stays in place underneath; users
    // dismiss via swipe-down or the in-modal CTAs.
    ref.listen(digestProvider, (previous, next) {
      next.whenData((digest) {
        if (digest != null &&
            digest.isCompleted &&
            previous?.value?.isCompleted != true) {
          _showClosureModal(digest.digestId);
        }
      });
    });

    // Background is static — only the card changes color per mode
    return Stack(
      children: [
        Container(
          color: colors.backgroundPrimary,
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: ModeAccent(isSerein: sereinState.enabled),
          ),
        ),
        Scaffold(
          backgroundColor: Colors.transparent,
          body: SafeArea(
            child: RefreshIndicator(
              onRefresh: () async {
                // Refresh both the digest itself and the community 🌻 carousel
                // so newly-sunflowered articles appear after a pull-to-refresh.
                ref.invalidate(communityCarouselProvider);
                await ref.read(digestProvider.notifier).refreshDigest();
              },
              color: colors.primary,
              child: CustomScrollView(
                controller: _scrollController,
                slivers: [
                  // Header : back rond + titre majuscules
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: FacteurSpacing.space4,
                        vertical: FacteurSpacing.space2,
                      ),
                      child: Row(
                        children: [
                          _CircularBackButton(onTap: () => context.pop()),
                          const SizedBox(width: 12),
                          Text(
                            "L'ESSENTIEL DU JOUR",
                            style: FacteurTypography.stamp(
                                    colors.textTertiary)
                                .copyWith(
                              fontSize: 12,
                              letterSpacing: 1.4,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Hero : pill + titre + meta + illustration facteur
                  SliverToBoxAdapter(
                    child: DigestHero(
                      articleCount:
                          digestAsync.valueOrNull?.items.length ?? 5,
                      targetDate:
                          digestAsync.valueOrNull?.targetDate ?? DateTime.now(),
                      isSerein: sereinState.enabled,
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
                                  color: colors.success.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color:
                                        colors.success.withOpacity(0.3),
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
                                        final confirmed =
                                            await showDialog<bool>(
                                          context: context,
                                          builder: (context) => AlertDialog(
                                            title: const Text(
                                                'Générer un nouvel essentiel ?'),
                                            content: const Text(
                                              'Votre essentiel actuel sera remplacé par 5 nouveaux articles. Cette action est irréversible.',
                                            ),
                                            actions: [
                                              TextButton(
                                                onPressed: () => Navigator.pop(
                                                    context, false),
                                                child: const Text('Annuler'),
                                              ),
                                              FilledButton(
                                                onPressed: () => Navigator.pop(
                                                    context, true),
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
                                              .withOpacity(0.15),
                                          borderRadius:
                                              BorderRadius.circular(16),
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
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: digestAsync.when(
                        data: (digest) {
                          if (digest == null ||
                              (digest.items.isEmpty && digest.topics.isEmpty)) {
                            return _buildEmptyState(colors);
                          }

                          final notifier = ref.read(digestProvider.notifier);
                          final total = notifier.totalCount;
                          final userPref = ref.watch(onboardingProvider).answers.dailyArticleCount ?? 5;
                          final denominator = total < userPref ? total : userPref;

                          return DigestBriefingSection(
                            digest: digest,
                            items: digest.items,
                            topics: digest.usesTopics ? digest.topics : null,
                            processedCount: notifier.processedCount,
                            dailyGoal: denominator,
                            onItemTap: _openArticle,
                            onLike: _handleLike,
                            onSave: _handleSave,
                            onNotInterested: _handleNotInterested,
                            onReportNotSerene: sereinState.enabled
                                ? _handleReportNotSerene
                                : null,
                            onSwipeDismiss: _handleSwipeDismiss,
                            onSourceTap: (sourceId) {
                              ref.read(feedProvider.notifier).setSource(sourceId);
                              context.goNamed(RouteNames.feed);
                            },
                            onMuteSource: (sourceId) => ref
                                .read(feedProvider.notifier)
                                .muteSourceById(sourceId),
                            onMuteTopic: (topic) => ref
                                .read(feedProvider.notifier)
                                .muteTopic(topic),
                            isSerein: sereinState.enabled,
                            usesEditorial: digest.usesEditorial,
                            pepite: digest.usesEditorial ? digest.pepite : null,
                            coupDeCoeur: digest.usesEditorial
                                ? digest.coupDeCoeur
                                : null,
                            actuDecalee: digest.usesEditorial
                                ? digest.actuDecalee
                                : null,
                            headerText:
                                digest.usesEditorial ? digest.headerText : null,
                            closureText: digest.usesEditorial
                                ? digest.closureText
                                : null,
                            ctaText:
                                digest.usesEditorial ? digest.ctaText : null,
                            communityCarousel:
                                _filterCommunityCarousel(digest),
                            onCommunityArticleTap: (item) {
                              // Convert community carousel item to Content for navigation
                              final content = Content(
                                id: item.contentId,
                                title: item.title,
                                url: item.url,
                                thumbnailUrl: item.thumbnailUrl,
                                source: Source(
                                  id: item.sourceId ?? '',
                                  name: item.sourceName,
                                  type: SourceType.article,
                                  logoUrl: item.sourceLogoUrl,
                                ),
                                contentType: ContentType.article,
                                publishedAt: item.publishedAt ?? DateTime.now(),
                              );
                              context.pushNamed(
                                RouteNames.contentDetail,
                                pathParameters: {'id': item.contentId},
                                extra: content,
                              );
                            },
                          );
                        },
                        loading: () => _buildLoadingState(),
                        error: (error, stack) =>
                            _buildErrorState(context, ref, error),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return const LoadingView();
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
    Object error,
  ) {
    void retry() => ref.read(digestProvider.notifier).refreshDigest();
    if (_consecutiveErrorCount >= 2) {
      return LaurinFallbackView(onRetry: retry);
    }
    return FriendlyErrorView(error: error, onRetry: retry);
  }

  /// Converts DigestItem to Content for navigation and PersonalizationSheet
  Content _convertToContent(DigestItem item) {
    return Content(
      id: item.contentId,
      title: item.title,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      description: item.description,
      htmlContent: item.htmlContent,
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
      editorialBadge: item.badge,
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

class _CircularBackButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CircularBackButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface.withOpacity(0.9),
          ),
          alignment: Alignment.center,
          child: Icon(
            PhosphorIcons.arrowLeft(PhosphorIconsStyle.bold),
            size: 18,
            color: colors.textPrimary,
          ),
        ),
      ),
    );
  }
}
