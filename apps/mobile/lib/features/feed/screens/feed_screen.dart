import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../config/theme.dart';
import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/feed_provider.dart';
import '../widgets/welcome_banner.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../../widgets/design/facteur_button.dart';
import '../models/content_model.dart';
import '../widgets/feed_card.dart';
import '../widgets/filter_bar.dart';
import '../widgets/animated_feed_card.dart';
import '../widgets/caught_up_card.dart';
import '../../gamification/widgets/streak_indicator.dart';
import '../../gamification/widgets/daily_progress_indicator.dart';
import '../../gamification/providers/streak_provider.dart';
import '../../settings/providers/user_profile_provider.dart';
import '../providers/user_bias_provider.dart';
import '../../progress/widgets/progression_card.dart';
import '../../progress/repositories/progress_repository.dart';
import '../../../core/ui/notification_service.dart';
import '../widgets/briefing_section.dart';

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

// ...
  Future<void> _showArticleModal(Content content) async {
    // 1. Mark as consumed immediately (Facteur philosophy: Click = Read)
    // Applies to both Briefing and Feed items.
    if (mounted) {
      ref.read(feedProvider.notifier).markContentAsConsumed(content);

      // Update Streak after animation/transition completes
      Future<void>.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) {
          ref.read(streakProvider.notifier).refreshSilent();
        }
      });
    }

    // 2. Navigation / Opening
    // Desktop: Open in browser
    if (!kIsWeb &&
        (Platform.isMacOS || Platform.isWindows || Platform.isLinux)) {
      launchUrl(Uri.parse(content.url));
      return;
    }

    // Mobile: In-app reader
    await context.push<bool>(
      '/feed/content/${content.id}',
      extra: content,
    );

    // 3. Post-consumption Logic (Progression / Topics)
    // Executed upon return, regardless of result, since we force-consumed it.
    if (mounted) {
      final topic = content.progressionTopic;

      if (topic != null && topic.isNotEmpty) {
        // Check if already followed
        final progressAsync = ref.read(myProgressProvider);
        bool isFollowed = false;

        if (progressAsync.hasValue) {
          isFollowed = progressAsync.value!
              .any((p) => p.topic.toLowerCase() == topic.toLowerCase());
        }

        // Logic refined:
        // If NOT followed -> Show Dynamic Card in Feed (via setState)
        // If Followed -> Show SnackBar (Success validation)

        if (!isFollowed) {
          // Activate the card for this content ID
          setState(() {
            _activeProgressions[content.id] = topic;
          });
          // Scroll slightly to make sure it's visible if it's below?
          // Usually the user returns to the same scroll position.
        } else {
          // Already followed
          Future.delayed(const Duration(milliseconds: 500), () {
            if (mounted) {
              NotificationService.showSuccess(
                  'Quiz disponible pour le sujet "$topic" !');
            }
          });
        }
      }
    }
  }

  // _showProgressionCTA REMOVED

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
                  PhosphorIcons.shareNetwork(PhosphorIconsStyle.regular),
                  color: colors.textPrimary,
                ),
                title: Text(
                  'Copier le lien',
                  style: textTheme.bodyLarge?.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(context);
                  await Clipboard.setData(ClipboardData(text: content.url));
                  NotificationService.showInfo(
                      'Lien copié dans le presse-papier');
                },
              ),
              const Divider(),
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

  void _hideContent(Content content, HiddenReason reason) {
    ref.read(feedProvider.notifier).hideContent(content, reason);

    // Feedback
    NotificationService.showInfo('Contenu masqué');
  }

  @override
  Widget build(BuildContext context) {
    final feedAsync = ref.watch(feedProvider);
    final colors = context.facteurColors;

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
                    // Header
                    const SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.symmetric(
                          horizontal: FacteurSpacing.space6,
                          vertical: FacteurSpacing.space4,
                        ),
                        child: Center(child: FacteurLogo(size: 32)),
                      ),
                    ),

                    // Salutation
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
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

                                  if (profile.firstName != null &&
                                      profile.firstName!.isNotEmpty) {
                                    displayName = profile.firstName!;
                                  } else if (authUser?.email != null) {
                                    // Extraction du prénom de l'email (format boujon.laurin@... ou laurin.boujon@...)
                                    final part = authUser!.email!.split('@')[0];
                                    final subParts = part.contains('.')
                                        ? part.split('.')
                                        : part.split('-');

                                    // On prend le segment qui n'est probablement pas le nom
                                    // ou par défaut le premier segment capitalisé
                                    if (subParts.length > 1) {
                                      // Heuristique simple : on capitalise le segment qui semble être le prénom
                                      // Souvent [nom].[prenom] ou [prenom].[nom]
                                      // On va prendre le dernier segment si il y en a un (souvent le cas pour les emails pro/scolaires)
                                      // ou rester sur le premier si c'est ambigu.
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
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Text(
                          'Voici vos news personnalisées du jour.',
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                    ),

                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: FilterBar(
                          selectedFilter:
                              ref.read(feedProvider.notifier).selectedFilter,
                          userBias: ref.watch(userBiasProvider).valueOrNull,
                          onFilterChanged: (String? filter) {
                            ref.read(feedProvider.notifier).setFilter(filter);
                          },
                        ),
                      ),
                    ),

                    const SliverToBoxAdapter(child: SizedBox(height: 16)),

                    // Feed Content
                    feedAsync.when(
                      data: (state) {
                        final contents = state.items;
                        final briefing = state.briefing;

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
                                // Index 0: Briefing
                                if (index == 0) {
                                  if (briefing.isNotEmpty) {
                                    return BriefingSection(
                                        briefing: briefing,
                                        onItemTap: (item) =>
                                            _showArticleModal(item.content));
                                  } else {
                                    return const SizedBox.shrink();
                                  }
                                }

                                final listIndex = index - 1;
                                final adjustedLength =
                                    contents.length + (showCaughtUp ? 1 : 0);

                                // Add loading indicator at the bottom
                                if (listIndex == adjustedLength) {
                                  final notifier =
                                      ref.read(feedProvider.notifier);
                                  if (notifier.hasNext) {
                                    return const Center(
                                        child: Padding(
                                            padding: EdgeInsets.all(16.0),
                                            child: CircularProgressIndicator
                                                .adaptive()));
                                  } else {
                                    return const SizedBox(height: 64);
                                  }
                                }

                                // Show caught-up card at position 3 (relative to feed list)
                                if (showCaughtUp &&
                                    listIndex == caughtUpIndex) {
                                  return Padding(
                                      key: const ValueKey('caught_up_card'),
                                      padding:
                                          const EdgeInsets.only(bottom: 16),
                                      child: CaughtUpCard(
                                          onDismiss: () => setState(() =>
                                              _caughtUpDismissed = true)));
                                }

                                final contentIndex =
                                    showCaughtUp && listIndex > caughtUpIndex
                                        ? listIndex - 1
                                        : listIndex;

                                if (contentIndex >= contents.length ||
                                    contentIndex < 0) {
                                  return const SizedBox.shrink();
                                }

                                final content = contents[contentIndex];
                                final isConsumed = ref
                                    .read(feedProvider.notifier)
                                    .isContentConsumed(content.id);
                                final progressionTopic =
                                    _activeProgressions[content.id];

                                return Padding(
                                  // Use composed key
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
                                          onMoreOptions: () {
                                            _showMoreOptions(context, content);
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
                              // Count: Briefing(1) + Contents + Loader(1) + CaughtUp(1?)
                              childCount: 1 +
                                  contents.length +
                                  1 +
                                  (showCaughtUp ? 1 : 0),
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
