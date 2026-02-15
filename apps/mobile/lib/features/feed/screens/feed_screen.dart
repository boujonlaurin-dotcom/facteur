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
import '../../../core/providers/navigation_providers.dart';
import '../providers/feed_provider.dart';
import '../widgets/welcome_banner.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../../widgets/design/facteur_button.dart';
import '../models/content_model.dart';
import '../widgets/feed_card.dart';
import '../widgets/personalization_sheet.dart';
import '../widgets/personalization_nudge.dart';
import '../providers/skip_provider.dart';
import '../widgets/filter_bar.dart';
import '../widgets/animated_feed_card.dart';
import '../widgets/caught_up_card.dart';
import '../../gamification/widgets/streak_indicator.dart';
import '../../gamification/widgets/daily_progress_indicator.dart';
import '../../gamification/providers/streak_provider.dart';
import '../../settings/providers/user_profile_provider.dart';
import '../providers/user_bias_provider.dart';
import '../providers/personalized_filters_provider.dart';
import '../providers/theme_filters_provider.dart';
import '../../progress/widgets/progression_card.dart';

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
  final int _itemsViewed = 0;

  // Dynamic progressions map: ContentID -> Topic
  final Map<String, String> _activeProgressions = {};

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  // Story 4.7: Track skips per source
  final Set<String> _viewedIds = {};

  void _recordSkipIfNecessary(int index, List<Content> contents) {
    if (index < 0 || index >= contents.length) return;
    final item = contents[index];
    if (!_viewedIds.contains(item.id)) {
      _viewedIds.add(item.id);
      ref.read(skipProvider.notifier).recordSkip(item.source.id);
    }
  }

  Future<void> _showArticleModal(Content content) async {
    // Interaction resets skips
    ref.read(skipProvider.notifier).recordInteraction(content.source.id);

    // 1. Mark as consumed immediately
    if (mounted) {
      ref.read(feedProvider.notifier).markContentAsConsumed(content);

      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) {
          ref.read(streakProvider.notifier).refreshSilent();
        }
      });
    }

    // 2. Navigation
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      launchUrl(Uri.parse(content.url));
      return;
    }

    await context.push<bool>(
      '/feed/content/${content.id}',
      extra: content,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final uri = GoRouterState.of(context).uri;
    if (uri.queryParameters['welcome'] == 'true' && !_showWelcome) {
      setState(() {
        _showWelcome = true;
      });
    }
  }

  @override
  void dispose() {
    // Track analytics before disposing controller
    // Note: ref may not be available during dispose in Riverpod, so we catch any errors
    try {
      // Only track if we have valid data and ref is still available
      if (_itemsViewed > 0) {
        final analytics = ref.read(analyticsServiceProvider);
        analytics.trackFeedScroll(_maxScrollPercent, _itemsViewed);
      }
    } catch (e) {
      // Silently ignore ref errors during dispose - widget is being cleaned up
      debugPrint('FeedScreen: Analytics tracking skipped during dispose');
    }
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;

    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.position.pixels;

    // Analytics
    if (maxScroll > 0) {
      final percent = (currentScroll / maxScroll).clamp(0.0, 1.0);
      if (percent > _maxScrollPercent) {
        _maxScrollPercent = percent;
      }
    }

    // Story 4.7: Detect skips
    // Estimate: Card ~350px (no briefing section in feed)
    final firstVisibleIndex = (currentScroll / 350).floor();
    if (firstVisibleIndex > 0) {
      final state = ref.read(feedProvider).value;
      if (state != null) {
        for (int i = 0; i < firstVisibleIndex && i < state.items.length; i++) {
          _recordSkipIfNecessary(i, state.items);
        }
      }
    }

    // Load more
    if (currentScroll >= maxScroll - 200) {
      ref.read(feedProvider.notifier).loadMore();
    }
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

  void _dismissWelcome() {
    setState(() {
      _showWelcome = false;
    });
    context.go(RoutePaths.feed);
  }

  Future<void> _refresh() async {
    return ref.read(feedProvider.notifier).refresh();
  }

  void _showPersonalizationSheet(BuildContext context, Content content) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => PersonalizationSheet(content: content),
    );
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);
    final colors = context.facteurColors;

    // Listen to scroll to top trigger
    ref.listen(feedScrollTriggerProvider, (_, __) => _scrollToTop());

    return PopScope(
      canPop: false,
      child: Material(
        color: colors.backgroundPrimary,
        child: Stack(
          children: [
            SafeArea(
              child: RefreshIndicator(
                onRefresh: _refresh,
                color: colors.primary,
                child: CustomScrollView(
                  controller: _scrollController,
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space6,
                          vertical: FacteurSpacing.space4,
                        ),
                        child: Center(child: FacteurLogo(size: 32)),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(8, 16, 8, 4),
                        child: Row(
                          children: [
                            Expanded(
                              child: Builder(
                                builder: (context) {
                                  final profile =
                                      ref.watch(userProfileProvider);
                                  final authUser =
                                      ref.watch(authStateProvider).user;

                                  String displayName = 'Vous';
                                  if (profile.displayName != null &&
                                      profile.displayName!.isNotEmpty) {
                                    displayName = profile.displayName!;
                                  } else if (authUser?.userMetadata != null &&
                                      authUser!.userMetadata!['first_name'] != null &&
                                      (authUser.userMetadata!['first_name'] as String).isNotEmpty) {
                                    final firstName = authUser.userMetadata!['first_name'] as String;
                                    displayName = firstName[0].toUpperCase() +
                                        firstName.substring(1).toLowerCase();
                                  } else if (authUser?.email != null) {
                                    final part = authUser!.email!.split('@')[0];
                                    final subParts = part.contains('.')
                                        ? part.split('.')
                                        : part.split('-');
                                    if (subParts.length > 1) {
                                      final candidate = subParts.last.length > 2
                                          ? subParts.last
                                          : subParts.first;
                                      displayName = candidate[0].toUpperCase() +
                                          candidate.substring(1).toLowerCase();
                                    } else {
                                      displayName = part[0].toUpperCase() +
                                          part.substring(1).toLowerCase();
                                    }
                                  }
                                  return Text(
                                    'Bonjour $displayName,',
                                    style: Theme.of(context)
                                        .textTheme
                                        .displayMedium,
                                  );
                                },
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
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Text(
                          'Vos news personnalisées du jour.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4.0),
                        child: Builder(builder: (context) {
                          // Theme filters from API (Epic 11)
                          final themeFiltersAsync =
                              ref.watch(themeFiltersProvider);
                          final themeFilters =
                              themeFiltersAsync.valueOrNull ?? [];

                          final notifier = ref.read(feedProvider.notifier);

                          return FilterBar(
                            selectedFilter: notifier.selectedTheme,
                            userBias: ref.watch(userBiasProvider).valueOrNull,
                            availableFilters: themeFilters,
                            onFilterChanged: (String? filter) {
                              notifier.setTheme(filter);
                            },
                          );
                        }),
                      ),
                    ),
                    const SliverToBoxAdapter(child: SizedBox(height: 16)),
                    feedAsync.when(
                      data: (state) {
                        final contents = state.items;

                        final streakAsync = ref.watch(streakProvider);
                        final dailyCount =
                            streakAsync.valueOrNull?.weeklyCount ?? 0;
                        final showCaughtUp = dailyCount >= _caughtUpThreshold &&
                            !_caughtUpDismissed;
                        // Position de la carte "Tu es à jour" après 8 articles
                        const caughtUpPos = 8;

                        final skips = ref.watch(skipProvider);
                        final nudgeSourceId = skips.keys.firstWhere(
                          (id) => skips[id]! >= 3,
                          orElse: () => '',
                        );
                        // Ne pas afficher le nudge si la carte CaughtUp bloque le scroll
                        final showingNudge = !showCaughtUp &&
                            nudgeSourceId.isNotEmpty &&
                            contents.length > 5;
                        const nudgePos = 5;

                        // Calculer le childCount - TOUJOURS utiliser la formule normale
                        // Le blocage est géré dans le builder, pas par le childCount
                        final int effectiveChildCount = contents.length +
                            1 +
                            (showCaughtUp ? 1 : 0) +
                            (showingNudge ? 1 : 0);

                        return SliverPadding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          sliver: SliverList(
                            // Key pour forcer rebuild complet quand showCaughtUp change
                            key: ValueKey('feed_list_caught_up_$showCaughtUp'),
                            delegate: SliverChildBuilderDelegate(
                              (context, index) {
                                final listIndex = index;

                                // Interleaving logic - calculer l'offset pour les éléments intercalés
                                int contentOffset = 0;

                                // Caught up card - s'affiche après caughtUpPos articles
                                if (showCaughtUp) {
                                  if (listIndex == caughtUpPos) {
                                    return Padding(
                                        key: const ValueKey('caught_up_card'),
                                        padding:
                                            const EdgeInsets.only(bottom: 16),
                                        child: CaughtUpCard(onDismiss: () {
                                          setState(
                                              () => _caughtUpDismissed = true);
                                          // Forcer le chargement de plus d'articles
                                          ref
                                              .read(feedProvider.notifier)
                                              .loadMore();
                                        }));
                                  }
                                  if (listIndex > caughtUpPos) {
                                    // Après la carte : afficher un espace puis rien (bloque visuellement)
                                    // Mais on garde le childCount normal pour éviter les bugs
                                    return const SizedBox.shrink();
                                  }
                                  // Avant la carte : continuer normalement
                                }

                                // Compter la CaughtUpCard si elle est passée (pour le décalage)
                                if (showCaughtUp && listIndex > caughtUpPos) {
                                  contentOffset++;
                                }

                                // Personalization Nudge (seulement si CaughtUp n'est pas affiché)
                                if (showingNudge) {
                                  final nudgeEffectivePos =
                                      nudgePos + contentOffset;
                                  if (listIndex == nudgeEffectivePos) {
                                    final sourceName = contents
                                        .firstWhere(
                                            (c) => c.source.id == nudgeSourceId,
                                            orElse: () => contents.first)
                                        .source
                                        .name;
                                    return PersonalizationNudge(
                                      key: ValueKey('nudge_$nudgeSourceId'),
                                      sourceId: nudgeSourceId,
                                      sourceName: sourceName,
                                    );
                                  }
                                  if (listIndex > nudgeEffectivePos) {
                                    contentOffset++;
                                  }
                                }

                                final contentIndex = listIndex - contentOffset;

                                if (contentIndex >= contents.length) {
                                  if (ref.read(feedProvider.notifier).hasNext) {
                                    return const Center(
                                        child: Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: CircularProgressIndicator
                                                .adaptive()));
                                  }
                                  return const SizedBox(height: 64);
                                }

                                if (contentIndex < 0) {
                                  return const SizedBox.shrink();
                                }

                                final content = contents[contentIndex];
                                final isConsumed = ref
                                    .read(feedProvider.notifier)
                                    .isContentConsumed(content.id);
                                final progressionTopic =
                                    _activeProgressions[content.id];

                                return Padding(
                                  key: ValueKey(
                                      '${content.id}_${progressionTopic != null}'),
                                  padding: const EdgeInsets.only(bottom: 16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      AnimatedFeedCard(
                                        isConsumed: isConsumed,
                                        child: FeedCard(
                                          content: content,
                                          onTap: () =>
                                              _showArticleModal(content),
                                          onLike: () {
                                            ref
                                                .read(feedProvider.notifier)
                                                .toggleLike(content);
                                          },
                                          isLiked: content.isLiked,
                                          onSave: () {
                                            ref
                                                .read(feedProvider.notifier)
                                                .toggleSave(content);
                                          },
                                          isSaved: content.isSaved,
                                          onNotInterested: () {
                                            ref
                                                .read(feedProvider.notifier)
                                                .hideContent(
                                                    content,
                                                    HiddenReason.source);
                                          },
                                          onPersonalize: () {
                                            _showPersonalizationSheet(
                                                context, content);
                                          },
                                        ),
                                      ),
                                      if (progressionTopic != null) ...[
                                        TweenAnimationBuilder<double>(
                                          tween: Tween(begin: 0.0, end: 1.0),
                                          duration:
                                              const Duration(milliseconds: 500),
                                          curve: Curves.easeOutBack,
                                          builder: (context, value, child) {
                                            return Transform.scale(
                                              scale: value,
                                              child: Opacity(
                                                  opacity: value, child: child),
                                            );
                                          },
                                          child: ProgressionCard(
                                            topic: progressionTopic,
                                            onDismiss: () {
                                              setState(() {
                                                _activeProgressions
                                                    .remove(content.id);
                                              });
                                            },
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              },
                              childCount: effectiveChildCount,
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
                                        PhosphorIconsStyle.duotone),
                                    size: 48,
                                    color: colors.error),
                                const SizedBox(height: 16),
                                Text('Erreur de chargement',
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium),
                                Text(err.toString(),
                                    textAlign: TextAlign.center,
                                    style: Theme.of(context)
                                        .textTheme
                                        .bodySmall
                                        ?.copyWith(color: colors.error)),
                                const SizedBox(height: 16),
                                FacteurButton(
                                    label: 'Réessayer',
                                    icon: PhosphorIcons.arrowClockwise(
                                        PhosphorIconsStyle.bold),
                                    onPressed: () => ref.refresh(feedProvider)),
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
