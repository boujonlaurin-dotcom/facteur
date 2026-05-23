import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/section_banner.dart';

/// Distance to the bottom (in px) at which we trigger the next page of
/// articles for the current theme. Mirrors the threshold used on the main
/// Flux Continu screen so the feel of the infinite scroll is identical.
const double _kLoadMoreLeadingPx = 800.0;

/// Full-page view of a Tournée du jour theme section (a `FeedThemeSection`).
///
/// Surfaces the same hero banner as the inline section + the complete list of
/// articles with infinite scroll. Reuses [fluxContinuProvider.loadMoreTheme]
/// so any new article loaded here also propagates back to the main feed when
/// the user returns.
class ThemeSectionScreen extends ConsumerStatefulWidget {
  final String sectionKeyValue;

  /// Optional snapshot captured at navigation time. Used as the immediate
  /// render source while [fluxContinuProvider] is still loading, so the user
  /// doesn't see an empty page during the slide-in transition.
  final FeedThemeSection? initialSection;

  const ThemeSectionScreen({
    super.key,
    required this.sectionKeyValue,
    this.initialSection,
  });

  @override
  ConsumerState<ThemeSectionScreen> createState() =>
      _ThemeSectionScreenState();
}

class _ThemeSectionScreenState extends ConsumerState<ThemeSectionScreen> {
  final ScrollController _scroll = ScrollController();
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
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.maxScrollExtent - pos.pixels >= _kLoadMoreLeadingPx) return;
    if (_loadingMore) return;
    final section = _resolveSection();
    if (section == null || !section.hasMore || section.isLoadingMore) return;
    _loadingMore = true;
    ref
        .read(fluxContinuProvider.notifier)
        .loadMoreTheme(widget.sectionKeyValue)
        .whenComplete(() => _loadingMore = false);
  }

  FeedThemeSection? _resolveSection() {
    final state = ref.read(fluxContinuProvider).valueOrNull;
    if (state == null) return widget.initialSection;
    for (final s in state.sections) {
      if (s is FeedThemeSection && sectionKey(s) == widget.sectionKeyValue) {
        return s;
      }
    }
    return widget.initialSection;
  }

  void _openArticle(BuildContext context, Content article) {
    context.push(
      '${RoutePaths.fluxContinu}/content/${article.id}',
      extra: article,
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Watch the provider so the page rebuilds when loadMoreTheme appends
    // items. Falls back to [initialSection] until the provider has a value.
    ref.watch(fluxContinuProvider);
    final section = _resolveSection();
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: colors.textPrimary),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
        title: section == null
            ? null
            : Text(
                section.label,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
      ),
      body: section == null
          ? Center(
              child: Text(
                'Section introuvable',
                style: TextStyle(color: colors.textSecondary),
              ),
            )
          : CustomScrollView(
              controller: _scroll,
              physics: const AlwaysScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: SectionBanner(
                    title: section.label,
                    accent: section.accent,
                    blurb: section.blurb,
                    illustrationAsset: section.illustrationAsset,
                  ),
                ),
                SliverList(
                  delegate: SliverChildBuilderDelegate(
                    (context, index) {
                      final item = section.items[index];
                      return FluxContinuArticleCard(
                        article: item,
                        onTap: () => _openArticle(context, item),
                      );
                    },
                    childCount: section.items.length,
                  ),
                ),
                SliverToBoxAdapter(
                  child: _Footer(section: section),
                ),
                const SliverToBoxAdapter(
                  child: SizedBox(height: 60),
                ),
              ],
            ),
    );
  }
}

class _Footer extends StatelessWidget {
  final FeedThemeSection section;

  const _Footer({required this.section});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final String label;
    if (section.isLoadingMore) {
      label = 'Chargement…';
    } else if (section.hasMore) {
      label = '';
    } else {
      label = 'Plus rien à voir';
    }
    if (label.isEmpty) {
      return const SizedBox(height: 32);
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (section.isLoadingMore) ...[
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor:
                    AlwaysStoppedAnimation<Color>(colors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: TextStyle(
              color: colors.textSecondary,
              fontWeight: FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}
