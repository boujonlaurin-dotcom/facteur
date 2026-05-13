import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/orchestration/first_impression_orchestrator.dart';
import '../../../widgets/design/facteur_logo.dart';
import '../../app_update/providers/app_update_provider.dart';
import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/widgets/digest_entry_card.dart';
import '../../feed/widgets/follow_keyword_suggestion_card.dart';
import '../../feed/widgets/profile_avatar_button.dart';
import '../../gamification/widgets/streak_indicator.dart';
import '../../lettres/widgets/lettres_notification_banner.dart';
import '../../notifications/widgets/notification_renudge_banner.dart';
import '../../well_informed/widgets/well_informed_prompt.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../widgets/closing_card_v18.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/section_block.dart';
import '../widgets/section_hairline.dart';
import '../widgets/sticky_tab_bar.dart';

/// Scroll offset at which the AppBar is swapped with the sticky tab bar.
const double _kStickyThreshold = 60.0;

/// Vertical offset the sticky bar consumes — used as a landing buffer
/// when scrolling a section into view so its banner doesn't disappear
/// behind the bar.
const double _kStickyBarHeight = 86.0;

/// Distance to the bottom (in px) before we trigger the next feed page.
const double _kLoadMoreLeadingPx = 800.0;

class FluxContinuScreen extends ConsumerStatefulWidget {
  const FluxContinuScreen({super.key});

  @override
  ConsumerState<FluxContinuScreen> createState() => _FluxContinuScreenState();
}

class _FluxContinuScreenState extends ConsumerState<FluxContinuScreen> {
  final ScrollController _scroll = ScrollController();
  final ValueNotifier<double> _scrollOffset = ValueNotifier(0);
  final ValueNotifier<double> _scrollProgress = ValueNotifier(0);
  final ValueNotifier<int> _activeIndex = ValueNotifier(0);
  final GlobalKey _closingKey = GlobalKey();
  final List<GlobalKey> _sectionKeys = [];
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _scrollOffset.dispose();
    _scrollProgress.dispose();
    _activeIndex.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    _scrollOffset.value = pos.pixels;
    final max = pos.maxScrollExtent;
    _scrollProgress.value = max > 0 ? (pos.pixels / max).clamp(0.0, 1.0) : 0;
    _updateActiveSection();

    if (pos.maxScrollExtent - pos.pixels < _kLoadMoreLeadingPx &&
        !_loadingMore) {
      _loadingMore = true;
      ref
          .read(fluxContinuProvider.notifier)
          .loadMoreFeed()
          .whenComplete(() => _loadingMore = false);
    }
  }

  void _updateActiveSection() {
    if (_sectionKeys.isEmpty) return;
    int activeAt = 0;
    for (var i = 0; i < _sectionKeys.length; i++) {
      final ctx = _sectionKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final dy = box.localToGlobal(Offset.zero).dy;
      if (dy < _kStickyBarHeight + 32) {
        activeAt = i;
      }
    }
    if (_activeIndex.value != activeAt) _activeIndex.value = activeAt;
  }

  Future<void> _scrollToSection(int index) async {
    if (index < 0 || index >= _sectionKeys.length) return;
    final ctx = _sectionKeys[index].currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final scrollBox = _scroll.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (scrollBox == null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOut,
      );
      return;
    }
    final delta =
        box.localToGlobal(Offset.zero, ancestor: scrollBox).dy -
            _kStickyBarHeight;
    final target = (_scroll.offset + delta)
        .clamp(0.0, _scroll.position.maxScrollExtent);
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeInOut,
    );
  }

  void _openArticle(BuildContext context, Object article) {
    if (article is DigestItem) {
      context.push('${RoutePaths.fluxContinu}/content/${article.contentId}');
    } else if (article is Content) {
      context.push(
        '${RoutePaths.fluxContinu}/content/${article.id}',
        extra: article,
      );
    }
  }

  Future<void> _scrollToContinuation() async {
    final ctx = _closingKey.currentContext;
    if (ctx == null) return;
    await Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      alignment: 0,
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fluxContinuProvider);
    return Scaffold(
      backgroundColor: context.facteurColors.backgroundPrimary,
      body: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            state.when(
              loading: () => const _LoadingView(),
              error: (e, _) => _ErrorView(
                error: e,
                onRetry: () =>
                    ref.read(fluxContinuProvider.notifier).refresh(),
              ),
              data: (data) => _buildContent(context, data),
            ),
            _StickyTabBarOverlay(
              scrollOffset: _scrollOffset,
              scrollProgress: _scrollProgress,
              activeIndex: _activeIndex,
              stateProvider: fluxContinuProvider,
              onTapTab: _scrollToSection,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, FluxContinuState state) {
    final notifier = ref.read(fluxContinuProvider.notifier);
    final colors = context.facteurColors;
    final impressionSlot = ref.watch(firstImpressionSlotProvider);
    final keyword = ref.watch(feedProvider.notifier).selectedKeyword;
    final totalArticles = state.sections.fold<int>(
      0,
      (sum, s) => sum + s.articles.length,
    );

    if (_sectionKeys.length != state.sections.length) {
      _sectionKeys
        ..clear()
        ..addAll(List.generate(state.sections.length, (_) => GlobalKey()));
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      color: colors.primary,
      child: CustomScrollView(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: FacteurSpacing.space6,
                vertical: FacteurSpacing.space3,
              ),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const FacteurLogo(size: 22, showIcon: false),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: StreakIndicator(),
                  ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Consumer(builder: (context, ref, _) {
                      final hasUpdate = ref
                              .watch(appUpdateProvider)
                              .valueOrNull
                              ?.updateAvailable ==
                          true;
                      final settingsButton = ProfileAvatarButton(
                        onTap: () => context.push(RoutePaths.settings),
                      );
                      if (!hasUpdate) return settingsButton;
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          settingsButton,
                          Positioned(
                            top: -2,
                            right: -2,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: colors.error,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: colors.backgroundPrimary,
                                  width: 2,
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    }),
                  ),
                ],
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: impressionSlot == FirstImpressionSlot.renudgeBanner
                ? const NotificationRenudgeBanner()
                : const SizedBox.shrink(),
          ),
          SliverToBoxAdapter(
            child: impressionSlot == FirstImpressionSlot.wellInformed
                ? const WellInformedPrompt()
                : const SizedBox.shrink(),
          ),
          const SliverToBoxAdapter(
            child: LettresNotificationBanner(),
          ),
          const SliverToBoxAdapter(
            child: Padding(
              padding: EdgeInsets.only(top: 14, bottom: 8),
              child: DigestEntryCard(),
            ),
          ),
          SliverToBoxAdapter(
            child: (keyword == null || keyword.trim().isEmpty)
                ? const SizedBox.shrink()
                : FollowKeywordSuggestionCard(keyword: keyword),
          ),
          for (var i = 0; i < state.sections.length; i++)
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _sectionKeys[i],
                child: SectionBlock(
                  section: state.sections[i],
                  isOpen: state.isOpen(state.sections[i].kind),
                  onToggleMore: () =>
                      notifier.toggleMore(state.sections[i].kind),
                  onTapArticle: (a) => _openArticle(context, a),
                ),
              ),
            ),
          if (state.sections.isEmpty)
            SliverToBoxAdapter(
              child: _EmptySectionsHint(onRetry: notifier.refresh),
            ),
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _closingKey,
              child: ClosingCardV18(
                articleCount: totalArticles,
                onContinue: _scrollToContinuation,
              ),
            ),
          ),
          if (state.feedContinu.isNotEmpty) ...[
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, i) => FluxContinuArticleCard(
                  article: state.feedContinu[i],
                  onTap: () => _openArticle(context, state.feedContinu[i]),
                ),
                childCount: state.feedContinu.length,
              ),
            ),
            const SliverToBoxAdapter(child: SectionHairline()),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 60)),
        ],
      ),
    );
  }
}

/// Reveals the sticky tab bar over the content once the user scrolls past
/// the threshold. The header itself lives inside the scroll view, so it
/// simply disappears upward as content moves up.
class _StickyTabBarOverlay extends ConsumerWidget {
  final ValueNotifier<double> scrollOffset;
  final ValueNotifier<double> scrollProgress;
  final ValueNotifier<int> activeIndex;
  final AsyncNotifierProvider<FluxContinuNotifier, FluxContinuState>
      stateProvider;
  final ValueChanged<int> onTapTab;

  const _StickyTabBarOverlay({
    required this.scrollOffset,
    required this.scrollProgress,
    required this.activeIndex,
    required this.stateProvider,
    required this.onTapTab,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sections =
        ref.watch(stateProvider).valueOrNull?.sections ?? const <Section>[];
    return ValueListenableBuilder<double>(
      valueListenable: scrollOffset,
      builder: (context, offset, _) {
        final showSticky = offset > _kStickyThreshold && sections.isNotEmpty;
        return AnimatedSwitcher(
          duration: const Duration(milliseconds: 150),
          child: showSticky
              ? Positioned(
                  key: const ValueKey('sticky'),
                  top: 0,
                  left: 0,
                  right: 0,
                  child: ValueListenableBuilder<int>(
                    valueListenable: activeIndex,
                    builder: (context, idx, _) =>
                        ValueListenableBuilder<double>(
                      valueListenable: scrollProgress,
                      builder: (context, progress, _) => StickyTabBar(
                        sections: sections,
                        activeIndex: idx.clamp(0, sections.length - 1),
                        progress: progress,
                        onTapTab: onTapTab,
                      ),
                    ),
                  ),
                )
              : const SizedBox.shrink(key: ValueKey('hidden')),
        );
      },
    );
  }
}

class _LoadingView extends StatelessWidget {
  const _LoadingView();

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.only(top: 60),
      children: List.generate(
        4,
        (_) => const Padding(
          padding: EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space4,
            vertical: FacteurSpacing.space3,
          ),
          child: _Skeleton(),
        ),
      ),
    );
  }
}

class _Skeleton extends StatelessWidget {
  const _Skeleton();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      height: 96,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded,
                size: 48, color: colors.textTertiary),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              'Le flux continu est indisponible.',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: colors.textSecondary,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space4),
            OutlinedButton(
              onPressed: onRetry,
              child: const Text('Réessayer'),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptySectionsHint extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _EmptySectionsHint({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: colors.textTertiary),
          const SizedBox(height: 8),
          Text(
            'Pas encore de contenu pour la tournée du jour.',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(
            onPressed: onRetry,
            child: const Text('Recharger'),
          ),
        ],
      ),
    );
  }
}
