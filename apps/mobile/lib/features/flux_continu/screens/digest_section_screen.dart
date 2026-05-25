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

/// Full-page view of a [DigestTopicSection] (Actus du jour, Bonnes Nouvelles).
///
/// Renders the section's hero banner and every topic's lead article. Mirrors
/// [ThemeSectionScreen] visually so the dedicated-page UX is consistent
/// across all Tournée sections. The digest payload is bounded (no infinite
/// scroll) so we render the full list directly.
class DigestSectionScreen extends ConsumerWidget {
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

  DigestTopicSection? _resolveSection(WidgetRef ref) {
    final state = ref.watch(fluxContinuProvider).valueOrNull;
    if (state == null) return initialSection;
    for (final s in state.sections) {
      if (s is DigestTopicSection && sectionKey(s) == sectionKeyValue) {
        return s;
      }
    }
    return initialSection;
  }

  void _openArticle(BuildContext context, DigestItem article) {
    context.push('${RoutePaths.fluxContinu}/content/${article.contentId}');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final section = _resolveSection(ref);
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
                        isEssentiel:
                            section.kind == SectionKind.essentiel,
                        pressReviewCount: topic.perspectiveCount,
                        perspectiveSources: topic.perspectiveSources,
                        onTap: () => _openArticle(context, lead),
                      );
                    },
                    childCount: section.topics.length,
                  ),
                ),
                const SliverToBoxAdapter(child: SizedBox(height: 60)),
              ],
            ),
    );
  }
}
