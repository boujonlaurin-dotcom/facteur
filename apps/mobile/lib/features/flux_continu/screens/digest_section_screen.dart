import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../digest/models/digest_models.dart';
import '../models/flux_continu_models.dart';
import '../providers/flux_continu_provider.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/section_banner.dart';
import '../widgets/theme_detail_footer.dart';

/// Full-page view of a [DigestTopicSection] (Actus du jour, Bonnes Nouvelles).
///
/// Renders the section's hero banner and every topic's lead article. Mirrors
/// [ThemeSectionScreen] visually so the dedicated-page UX is consistent
/// across all Tournée sections. The digest payload is bounded (no infinite
/// scroll) so we render the full list directly, then attach a
/// [ThemeDetailFooter] with "Sujet suivant" / "Retour à la Tournée".
class DigestSectionScreen extends ConsumerStatefulWidget {
  final String sectionKeyValue;

  /// Snapshot captured at navigation time. Used as the immediate render
  /// source while [fluxContinuProvider] resolves, so the user doesn't see an
  /// empty page during the slide-in transition.
  final DigestTopicSection? initialSection;

  const DigestSectionScreen({
    super.key,
    required this.sectionKeyValue,
    this.initialSection,
  });

  @override
  ConsumerState<DigestSectionScreen> createState() =>
      _DigestSectionScreenState();
}

class _DigestSectionScreenState extends ConsumerState<DigestSectionScreen> {
  DigestTopicSection? _resolveSection() {
    final state = ref.watch(fluxContinuProvider).valueOrNull;
    if (state == null) return widget.initialSection;
    for (final s in state.sections) {
      if (s is DigestTopicSection && sectionKey(s) == widget.sectionKeyValue) {
        return s;
      }
    }
    return widget.initialSection;
  }

  void _openArticle(BuildContext context, DigestItem article) {
    context.push('${RoutePaths.fluxContinu}/content/${article.contentId}');
  }

  void _onBackToTournee() {
    Navigator.of(context).maybePop();
  }

  void _onTapNextSection(FluxSection next) {
    final key = Uri.encodeComponent(sectionKey(next));
    final path = next is FeedThemeSection
        ? '${RoutePaths.fluxContinu}/theme/$key'
        : '${RoutePaths.fluxContinu}/section/$key';
    context.pushReplacement(path, extra: next);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
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
          : _buildBody(section),
    );
  }

  Widget _buildBody(DigestTopicSection section) {
    final state = ref.watch(fluxContinuProvider).valueOrNull;
    final next = state == null
        ? null
        : nextSectionAfter(state.sections, widget.sectionKeyValue);
    return CustomScrollView(
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
              final topic = section.topics[index];
              final lead = pickTopicLead(topic);
              return FluxContinuArticleCard(
                article: lead,
                isEssentiel: section.kind == SectionKind.essentiel,
                pressReviewCount: topic.perspectiveCount,
                perspectiveSources: topic.perspectiveSources,
                onTap: () => _openArticle(context, lead),
              );
            },
            childCount: section.topics.length,
          ),
        ),
        SliverToBoxAdapter(
          child: ThemeDetailFooter(
            sectionLabel: section.label,
            nextSection: next,
            onTapBackToTournee: _onBackToTournee,
            onTapNextSection:
                next == null ? null : () => _onTapNextSection(next),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 40)),
      ],
    );
  }
}
