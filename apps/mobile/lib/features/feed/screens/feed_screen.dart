import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/feed_provider.dart';
import '../widgets/welcome_banner.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../../widgets/design/facteur_button.dart';
import '../../../config/constants.dart';
import '../models/content_model.dart';
import '../widgets/feed_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/article_viewer_modal.dart';
import '../widgets/animated_feed_card.dart';
import '../widgets/caught_up_card.dart';
import '../../gamification/widgets/streak_indicator.dart';
import '../../gamification/widgets/daily_progress_indicator.dart';
import '../../gamification/providers/streak_provider.dart';

/// Écran principal du feed
class FeedScreen extends ConsumerStatefulWidget {
  const FeedScreen({super.key});

  @override
  ConsumerState<FeedScreen> createState() => _FeedScreenState();
}

class _FeedScreenState extends ConsumerState<FeedScreen> {
  bool _showWelcome = false;
  bool _caughtUpDismissed = false;
  static const int _caughtUpThreshold = 8;
  final ScrollController _scrollController = ScrollController();
  double _maxScrollPercent = 0.0;
  int _itemsViewed = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Lire le paramètre welcome de l'URL
    final uri = GoRouterState.of(context).uri;
    if (uri.queryParameters['welcome'] == 'true' && !_showWelcome) {
      setState(() {
        _showWelcome = true;
      });
    }
  }

  @override
  void dispose() {
    // Capture des ressources avant la destruction
    try {
      final analytics = ref.read(analyticsServiceProvider);
      analytics.trackFeedScroll(_maxScrollPercent, _itemsViewed);
    } catch (e) {
      debugPrint('FeedScreen: Could not track analytics on dispose: $e');
    }

    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Update max scroll percent
    if (_scrollController.hasClients) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.position.pixels;
      if (maxScroll > 0) {
        final percent = (currentScroll / maxScroll).clamp(0.0, 1.0);
        if (percent > _maxScrollPercent) {
          _maxScrollPercent = percent;
        }
      }
    }

    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more when reading bottom
      ref.read(feedProvider.notifier).loadMore();
    }
  }

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
    });

    // Nettoyer l'URL (enlever le paramètre welcome)
    context.go(RoutePaths.feed);
  }

  Future<void> _refresh() async {
    // Explicit refresh call
    return ref.read(feedProvider.notifier).refresh();
  }

  void _showMoreOptions(BuildContext context, Content content) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: context.facteurColors.backgroundSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        final colors = context.facteurColors;
        // ignore: unused_local_variable
        final textTheme = Theme.of(context).textTheme;

        final sourceName = content.source.name;
        final topicName = content.source.theme;

        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 8),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 8),
              ListTile(
                leading: Icon(
                  PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                  color: colors.textPrimary,
                ),
                title: RichText(
                  text: TextSpan(
                    text: 'Voir moins de ',
                    style: textTheme.bodyLarge?.copyWith(
                      color: colors.textPrimary,
                    ),
                    children: [
                      TextSpan(
                        text: sourceName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _hideContent(content, HiddenReason.source);
                },
              ),
              if (topicName != null && topicName.isNotEmpty) ...[
                const Divider(),
                ListTile(
                  leading: Icon(
                    PhosphorIcons.hash(PhosphorIconsStyle.regular),
                    color: colors.textPrimary,
                  ),
                  title: RichText(
                    text: TextSpan(
                      text: 'Voir moins sur le sujet ',
                      style: textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                      ),
                      children: [
                        TextSpan(
                          text: topicName,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _hideContent(content, HiddenReason.topic);
                  },
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  void _showArticleModal(Content content) {
    // Si on est sur Desktop (macOS, Windows, Linux) hors Web, on ouvre direct dans le navigateur
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      launchUrl(Uri.parse(content.url));

      // Sur desktop on marque tout de suite comme consommé car pas de modal
      if (mounted) {
        ref.read(feedProvider.notifier).markContentAsConsumed(content);

        // Update Streak after animation completes
        Future<void>.delayed(const Duration(milliseconds: 1100), () {
          if (mounted) {
            ref.read(streakProvider.notifier).refreshSilent();
          }
        });
      }
      return;
    }

    // Sinon (Mobile/Web), on utilise la modal WebView
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      useSafeArea: true,
      builder: (context) => ArticleViewerModal(content: content),
    ).then((_) {
      // Au retour (fermeture de la modal), marquer comme consommé si monté
      if (mounted) {
        ref.read(feedProvider.notifier).markContentAsConsumed(content);

        // Update Streak after animation completes (1 second delay)
        Future<void>.delayed(const Duration(milliseconds: 1100), () {
          if (mounted) {
            ref.read(streakProvider.notifier).refreshSilent();
          }
        });
      }
    });
  }

  void _hideContent(Content content, HiddenReason reason) {
    ref.read(feedProvider.notifier).hideContent(content, reason);

    // Feedback
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: const Text("Contenu masqué"),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authStateProvider);
    final feedAsync = ref.watch(feedProvider);
    final colors = context.facteurColors;

    return PopScope(
      canPop: false,
      child: Scaffold(
        body: Stack(
          children: [
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: colors.primary,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    // Header
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space6,
                          vertical: FacteurSpacing.space4,
                        ),
                        child: Center(child: const FacteurLogo(size: 32)),
                      ),
                    ),

                    // Salutation
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Bonjour ${authState.user?.email?.split('@')[0] ?? 'Vous'},',
                                style: Theme.of(
                                  context,
                                ).textTheme.displayMedium,
                              ),
                            ),
                            const StreakIndicator(),
                            const SizedBox(width: 8),
                            const DailyProgressIndicator(),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Voici votre tournée du jour.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: FilterBar(
                        selectedFilter:
                            ref.read(feedProvider.notifier).selectedFilter,
                        onFilterChanged: (String? filter) {
                          ref.read(feedProvider.notifier).setFilter(filter);
                        },
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    // Feed Content
                    feedAsync.when(
                      data: (contents) {
                        // Check streak for caught-up card (computed outside builder for childCount access)
                        final streakAsync = ref.watch(streakProvider);
                        final dailyCount =
                            streakAsync.valueOrNull?.weeklyCount ?? 0;
                        final showCaughtUp = dailyCount >= _caughtUpThreshold &&
                            !_caughtUpDismissed;
                        final caughtUpIndex = showCaughtUp ? 3 : -1;

                        return SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          sliver: SliverList(
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final adjustedLength =
                                    contents.length + (showCaughtUp ? 1 : 0);

                                // Add loading indicator at the bottom
                                if (index == adjustedLength) {
                                  final notifier = ref.read(
                                    feedProvider.notifier,
                                  );
                                  if (notifier.hasNext) {
                                    return const Center(
                                      child: Padding(
                                        padding: EdgeInsets.all(16.0),
                                        child: CircularProgressIndicator
                                            .adaptive(),
                                      ),
                                    );
                                  } else {
                                    return const SizedBox(height: 64);
                                  }
                                }

                                // Show caught-up card at position 3
                                if (showCaughtUp && index == caughtUpIndex) {
                                  // Track completion if shown
                                  // We use addPostFrameCallback to avoid build-time side effects
                                  // logging only once per session/screen view would be better but duplicate events are okay for now
                                  // or we can use a flag

                                  return Padding(
                                    key: const ValueKey('caught_up_card'),
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: CaughtUpCard(
                                      onDismiss: () {
                                        setState(
                                          () => _caughtUpDismissed = true,
                                        );
                                      },
                                    ),
                                  );
                                }

                                // Adjust content index for caught-up card
                                final contentIndex =
                                    showCaughtUp && index > caughtUpIndex
                                        ? index - 1
                                        : index;

                                if (contentIndex >= contents.length) {
                                  return const SizedBox.shrink();
                                }

                                final content = contents[contentIndex];
                                final isConsumed = ref
                                    .read(feedProvider.notifier)
                                    .isContentConsumed(content.id);

                                // Update items viewed count approx
                                if (index > _itemsViewed) {
                                  _itemsViewed = index;
                                  // Track completion if we reached the end or caught up
                                  if (showCaughtUp && index >= caughtUpIndex) {
                                    // This is dynamic tracking, maybe simpler in onScroll?
                                    // Let's Stick to scroll depth + explicit "caught up" card check
                                    if (contentIndex == caughtUpIndex) {
                                      ref
                                          .read(analyticsServiceProvider)
                                          .trackFeedComplete();
                                    }
                                  }
                                }

                                return Padding(
                                  key: ValueKey(content.id),
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: AnimatedFeedCard(
                                    isConsumed: isConsumed,
                                    child: FeedCard(
                                      content: content,
                                      onTap: () => _showArticleModal(content),
                                      onBookmark: () {
                                        ref
                                            .read(feedProvider.notifier)
                                            .toggleSave(content);

                                        ScaffoldMessenger.of(context)
                                          ..hideCurrentSnackBar()
                                          ..showSnackBar(
                                            SnackBar(
                                              content: Text(
                                                UIConstants.savedConfirmMessage(
                                                  UIConstants.savedSectionName,
                                                ),
                                              ),
                                              action: SnackBarAction(
                                                label: 'Annuler',
                                                textColor: colors.primary,
                                                onPressed: () {
                                                  ref
                                                      .read(
                                                        feedProvider.notifier,
                                                      )
                                                      .toggleSave(content);
                                                },
                                              ),
                                              behavior:
                                                  SnackBarBehavior.floating,
                                              duration: const Duration(
                                                seconds: 2,
                                              ),
                                            ),
                                          );
                                      },
                                      isBookmarked: content.isSaved,
                                      onMoreOptions: () {
                                        _showMoreOptions(context, content);
                                      },
                                    ),
                                  ),
                                );
                              },
                              // Add +1 for the loader/spacer, +1 if showing caught-up card
                              childCount:
                                  contents.length + 1 + (showCaughtUp ? 1 : 0),
                            ),
                          ),
                        );
                      },
                      loading: () => SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: CircularProgressIndicator(
                              color: colors.primary,
                            ),
                          ),
                        ),
                      ),
                      error: (err, stack) => SliverToBoxAdapter(
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                Icon(
                                  PhosphorIcons.warning(
                                    PhosphorIconsStyle.duotone,
                                  ),
                                  size: 48,
                                  color: colors.error,
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  'Erreur de chargement',
                                  style: Theme.of(
                                    context,
                                  ).textTheme.titleMedium,
                                ),
                                Text(
                                  err.toString(), // A améliorer pour prod
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(color: colors.error),
                                ),
                                const SizedBox(height: 16),
                                FacteurButton(
                                  label: "Réessayer",
                                  icon: PhosphorIcons.arrowClockwise(
                                    PhosphorIconsStyle.bold,
                                  ),
                                  onPressed: () => ref.refresh(feedProvider),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (_showWelcome)
              Positioned.fill(
                child: SafeArea(
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: WelcomeBanner(
                      onDismiss: _dismissWelcome,
                      secondaryMessage: null,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
