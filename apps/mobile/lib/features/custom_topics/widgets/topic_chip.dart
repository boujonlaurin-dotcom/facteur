import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../core/ui/notification_service.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../../../core/api/providers.dart';
import '../models/topic_models.dart';
import '../providers/algorithm_profile_provider.dart';
import '../providers/custom_topics_provider.dart';
import '../providers/personalization_provider.dart';
import 'topic_priority_slider.dart';
import '../../../widgets/design/priority_slider.dart';
import '../../sources/providers/sources_providers.dart';

/// Terracotta accent color for custom topics.
const Color _terracotta = Color(0xFFE07A5F);

/// Which section of the ArticleSheet should be initially expanded.
enum ArticleSheetSection { topic, source, entities, breakdown, personalize }

/// Discreet topic tag in the feed card footer.
///
/// Renders as subtle inline text embedded in the footer row.
/// [isFollowed] must be provided by the parent to avoid per-chip provider watches.
/// Tap opens the unified article sheet.
class TopicChip extends StatelessWidget {
  final Content content;
  final bool isFollowed;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const TopicChip({
    super.key,
    required this.content,
    this.isFollowed = false,
    this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (content.topics.isEmpty) return const SizedBox.shrink();

    final topicSlug = content.topics.first;
    final topicLabel = getTopicLabel(topicSlug);
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap ?? () => showArticleSheet(context, content),
      onLongPress: onLongPress ??
          () => showArticleSheet(context, content,
              initialSection: ArticleSheetSection.topic),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: isFollowed
              ? Color.lerp(colors.backgroundSecondary, Colors.black, 0.008)!
              : Color.lerp(colors.backgroundSecondary, Colors.black, 0.003)!,
          borderRadius: BorderRadius.circular(8),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 80),
          child: Text(
            topicLabel,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: colors.textTertiary,
                  fontWeight: FontWeight.w500,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }

  /// Opens the unified article sheet with blur backdrop.
  static Future<void> showArticleSheet(
    BuildContext context,
    Content content, {
    ArticleSheetSection initialSection = ArticleSheetSection.topic,
  }) {
    final topicSlug = content.topics.isNotEmpty ? content.topics.first : '';
    final topicLabel =
        topicSlug.isNotEmpty ? getTopicLabel(topicSlug) : '';
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: ArticleSheet(
          content: content,
          topicSlug: topicSlug,
          topicLabel: topicLabel,
          initialSection: initialSection,
        ),
      ),
    );
  }
}

/// Unified modal sheet combining topic controls + source controls +
/// entity follow/unfollow + article personalization.
///
/// All sections are collapsible. [initialSection] determines which one
/// starts expanded; the others start collapsed.
class ArticleSheet extends ConsumerStatefulWidget {
  final Content content;
  final String topicSlug;
  final String topicLabel;
  final ArticleSheetSection initialSection;

  const ArticleSheet({
    super.key,
    required this.content,
    required this.topicSlug,
    required this.topicLabel,
    this.initialSection = ArticleSheetSection.topic,
  });

  @override
  ConsumerState<ArticleSheet> createState() => _ArticleSheetState();
}

class _ArticleSheetState extends ConsumerState<ArticleSheet> {
  late bool _topicExpanded;
  late bool _sourceExpanded;
  late bool _entitiesExpanded;
  late bool _breakdownExpanded;
  bool _breakdownShowAll = false;
  late bool _personalizeExpanded;

  @override
  void initState() {
    super.initState();
    final reason = widget.content.recommendationReason;
    _topicExpanded =
        widget.initialSection == ArticleSheetSection.topic;
    _sourceExpanded =
        widget.initialSection == ArticleSheetSection.source;
    _entitiesExpanded =
        widget.initialSection == ArticleSheetSection.entities;
    _breakdownExpanded =
        widget.initialSection == ArticleSheetSection.breakdown &&
            reason != null &&
            reason.breakdown.isNotEmpty;
    _personalizeExpanded =
        widget.initialSection == ArticleSheetSection.personalize ||
            widget.initialSection == ArticleSheetSection.source ||
            widget.initialSection == ArticleSheetSection.topic;
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final colorScheme = Theme.of(context).colorScheme;
    final reason = widget.content.recommendationReason;

    final topicsAsync = ref.watch(customTopicsProvider);
    final topics = topicsAsync.valueOrNull ?? [];
    final matchingTopics = topics.where(
      (t) =>
          t.slugParent == widget.topicSlug ||
          t.name.toLowerCase() == widget.topicLabel.toLowerCase(),
    );
    final isFollowed = matchingTopics.isNotEmpty;
    final matchedTopic = isFollowed ? matchingTopics.first : null;
    final parentLabel = getTopicMacroTheme(widget.topicSlug);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.80,
      ),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
      child: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Drag handle
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.textTertiary.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space3),

              // ── Section 1: Topic ──
              if (widget.topicSlug.isNotEmpty) ...[
                _buildSectionHeader(
                  context,
                  titleWidget: RichText(
                    text: TextSpan(
                      children: [
                        TextSpan(
                          text: widget.topicLabel,
                          style: textTheme.displaySmall?.copyWith(
                            fontSize: 20,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        TextSpan(
                          text: '  (sujet)',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
                  subtitle: parentLabel != null
                      ? '${getMacroThemeEmoji(parentLabel)} $parentLabel'
                      : null,
                  isExpanded: _topicExpanded,
                  onToggle: () =>
                      setState(() => _topicExpanded = !_topicExpanded),
                ),
                if (_topicExpanded) ...[
                  const SizedBox(height: FacteurSpacing.space4),
                  _buildTopicContent(
                    isFollowed: isFollowed,
                    matchedTopic: matchedTopic,
                    colorScheme: colorScheme,
                    colors: colors,
                    textTheme: textTheme,
                  ),
                ],
              ],

              // ── Section 2: Source ──
              if (widget.content.source.name.isNotEmpty) ...[
                const SizedBox(height: FacteurSpacing.space2),
                Divider(color: colors.textTertiary.withOpacity(0.2)),
                const SizedBox(height: FacteurSpacing.space3),
                _buildSectionHeader(
                  context,
                  titleWidget: Row(
                    children: [
                      if (widget.content.source.logoUrl != null &&
                          widget.content.source.logoUrl!.isNotEmpty) ...[
                        ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.network(
                            widget.content.source.logoUrl!,
                            width: 28,
                            height: 28,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) =>
                                const SizedBox.shrink(),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            RichText(
                              text: TextSpan(
                                children: [
                                  TextSpan(
                                    text: widget.content.source.name,
                                    style: textTheme.displaySmall?.copyWith(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  TextSpan(
                                    text: '  (source)',
                                    style: textTheme.labelSmall?.copyWith(
                                      color: colors.textTertiary,
                                      fontWeight: FontWeight.w400,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            if (widget.content.source.theme != null &&
                                widget.content.source.theme!.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                widget.content.source.getThemeLabel(),
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.textTertiary,
                                  letterSpacing: 1.0,
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  isExpanded: _sourceExpanded,
                  onToggle: () =>
                      setState(() => _sourceExpanded = !_sourceExpanded),
                ),
                if (_sourceExpanded) ...[
                  const SizedBox(height: FacteurSpacing.space3),
                  _buildSourceContent(
                      colorScheme: colorScheme,
                      colors: colors,
                      textTheme: textTheme),
                ],
              ],

              // ── Section 3: Entities ──
              if (widget.content.entities.isNotEmpty) ...[
                const SizedBox(height: FacteurSpacing.space2),
                Divider(color: colors.textTertiary.withOpacity(0.2)),
                const SizedBox(height: FacteurSpacing.space3),
                _buildSectionHeader(
                  context,
                  icon: PhosphorIcons.userCircle(PhosphorIconsStyle.regular),
                  iconColor: colors.textSecondary,
                  title: 'Sujets de cet article',
                  isExpanded: _entitiesExpanded,
                  onToggle: () =>
                      setState(() => _entitiesExpanded = !_entitiesExpanded),
                ),
                if (_entitiesExpanded) ...[
                  const SizedBox(height: 12),
                  _buildEntitiesContent(
                      topics: topics, colors: colors, textTheme: textTheme),
                ],
              ],

              // ── Section 4: "Pourquoi cet article ?" ──
              if (reason != null && reason.breakdown.isNotEmpty) ...[
                const SizedBox(height: FacteurSpacing.space2),
                Divider(color: colors.textTertiary.withOpacity(0.2)),
                const SizedBox(height: FacteurSpacing.space3),
                _buildSectionHeader(
                  context,
                  icon: PhosphorIcons.question(PhosphorIconsStyle.bold),
                  iconColor: colors.primary,
                  title: 'Pourquoi cet article ?',
                  trailing: reason.scoreTotal > 0
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: colors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            '${reason.scoreTotal.toInt()} pts',
                            style: TextStyle(
                              color: colors.primary,
                              fontSize: 14,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        )
                      : null,
                  isExpanded: _breakdownExpanded,
                  onToggle: () =>
                      setState(() => _breakdownExpanded = !_breakdownExpanded),
                ),
                if (_breakdownExpanded) ...[
                  const SizedBox(height: 12),
                  ..._buildBreakdownList(reason, colors),
                ],
              ],

              // ── Section 5: "Personnaliser mon flux" ──
              const SizedBox(height: FacteurSpacing.space2),
              Divider(color: colors.textTertiary.withOpacity(0.2)),
              const SizedBox(height: FacteurSpacing.space3),
              _buildSectionHeader(
                context,
                title: 'PERSONNALISER MON FLUX',
                isExpanded: _personalizeExpanded,
                onToggle: () => setState(
                    () => _personalizeExpanded = !_personalizeExpanded),
              ),
              if (_personalizeExpanded) ...[
                const SizedBox(height: 12),
                _buildActionOption(
                  context,
                  icon: PhosphorIcons.eyeClosed(PhosphorIconsStyle.regular),
                  label: "J'ai déjà vu cet article",
                  onTap: () async {
                    Navigator.pop(context);
                    try {
                      await ref
                          .read(feedProvider.notifier)
                          .impressContent(widget.content);
                      NotificationService.showInfo(
                          'Article marqué comme déjà vu');
                    } catch (e) {
                      NotificationService.showError(
                          'Erreur réseau — réessaie dans un instant');
                    }
                  },
                  colors: colors,
                ),
              ],

              const SizedBox(height: FacteurSpacing.space2),
            ],
          ),
        ),
      ),
    );
  }

  // ── Compact badges row (unused for now) ──
  // ignore: unused_element
  Widget _buildCompactBadgesRow() => const SizedBox.shrink();
  // ── Topic content ──

  Widget _buildTopicContent({
    required bool isFollowed,
    required UserTopicProfile? matchedTopic,
    required ColorScheme colorScheme,
    required FacteurColors colors,
    required TextTheme textTheme,
  }) {
    if (isFollowed && matchedTopic != null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _terracotta.withOpacity(0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
              border: Border.all(color: _terracotta.withOpacity(0.2)),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: _terracotta,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Suivi',
                        style: textTheme.labelMedium?.copyWith(
                          color: _terracotta,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '/',
                        style: textTheme.labelSmall?.copyWith(
                          color: colors.textTertiary,
                        ),
                      ),
                      const SizedBox(width: 6),
                      GestureDetector(
                        onTap: () async {
                          Navigator.pop(context);
                          try {
                            await ref
                                .read(customTopicsProvider.notifier)
                                .unfollowTopic(matchedTopic.id);
                            NotificationService.showInfo(
                              '${widget.topicLabel} retiré de vos sujets',
                            );
                          } catch (e) {
                            NotificationService.showError(
                              'Impossible de retirer le sujet',
                            );
                          }
                        },
                        child: Text(
                          'Ne plus suivre',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.error,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                Builder(builder: (context) {
                  final algoProfile = ref.watch(algorithmProfileProvider).valueOrNull;
                  final topicSlug = matchedTopic.slugParent;
                  final topicUsage = algoProfile != null &&
                          algoProfile.subtopicWeights.containsKey(topicSlug)
                      ? algoProfile.normalizeWeight(
                          algoProfile.subtopicWeights[topicSlug]!)
                      : null;
                  return TopicPrioritySlider(
                    currentMultiplier: matchedTopic.priorityMultiplier,
                    onChanged: (multiplier) async {
                      try {
                        await ref
                            .read(customTopicsProvider.notifier)
                            .updatePriority(matchedTopic.id, multiplier);
                      } on DioException catch (e) {
                        if (context.mounted) {
                          final detail = e.response?.data;
                          final msg =
                              (detail is Map && detail['detail'] is String)
                                  ? detail['detail'] as String
                                  : 'Erreur lors de la mise à jour';
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(msg),
                              duration: const Duration(seconds: 3),
                            ),
                          );
                        }
                      }
                    },
                    usageWeight: topicUsage,
                    onReset: topicUsage != null
                        ? () async {
                            final client = ref.read(apiClientProvider);
                            await client.post('/users/subtopics/$topicSlug/reset');
                            ref.invalidate(algorithmProfileProvider);
                          }
                        : null,
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                final router = GoRouter.of(context);
                Navigator.of(context).pop();
                router.pushNamed(RouteNames.myInterests);
              },
              icon: Icon(
                PhosphorIcons.gear(),
                size: 14,
                color: colors.textSecondary,
              ),
              label: Text(
                'Gérer mes intérêts',
                style: textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: () async {
              try {
                await ref
                    .read(customTopicsProvider.notifier)
                    .followTopic(widget.topicLabel,
                        slugParent: widget.topicSlug);
              } on DioException catch (e) {
                if (context.mounted) {
                  final detail = e.response?.data;
                  final msg = (detail is Map && detail['detail'] is String)
                      ? detail['detail'] as String
                      : 'Erreur lors de l\'ajout de ${widget.topicLabel}';
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(msg),
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
              }
            },
            icon: Icon(
              PhosphorIcons.plus(),
              size: 16,
              color: Colors.white,
            ),
            label: const Text(
              'Suivre ce sujet',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 15,
              ),
            ),
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.primary,
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: GestureDetector(
            onTap: () async {
              Navigator.pop(context);
              try {
                final repo = ref.read(personalizationRepositoryProvider);
                for (final topicSlug in widget.content.topics) {
                  await repo.muteTopic(topicSlug);
                }
                ref.invalidate(personalizationProvider);
                NotificationService.showInfo('Sujet masqué');
              } catch (e) {
                NotificationService.showError(
                  'Impossible de masquer le sujet',
                );
              }
            },
            child: Text(
              'Masquer ce sujet',
              style: textTheme.labelSmall?.copyWith(
                color: colors.error,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Center(
          child: TextButton.icon(
            style: TextButton.styleFrom(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              minimumSize: Size.zero,
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            onPressed: () {
              final router = GoRouter.of(context);
              Navigator.of(context).pop();
              router.pushNamed(RouteNames.myInterests);
            },
            icon: Icon(
              PhosphorIcons.gear(),
              size: 14,
              color: colors.textSecondary,
            ),
            label: Text(
              'Gérer mes intérêts',
              style: textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  // ── Source content ──

  Widget _buildSourceContent({
    required ColorScheme colorScheme,
    required FacteurColors colors,
    required TextTheme textTheme,
  }) {
    return Builder(builder: (context) {
      final sourcesAsync = ref.watch(userSourcesProvider);
      final sourceMatch = sourcesAsync.whenOrNull(
        data: (sources) => sources
            .where((s) => s.id == widget.content.source.id)
            .firstOrNull,
      );
      final currentMultiplier = sourceMatch?.priorityMultiplier ?? 1.0;
      final isTrustedAndActive =
          sourceMatch?.isTrusted == true && sourceMatch?.isMuted != true;
      final isSubscribed = sourceMatch?.hasSubscription ?? false;

      if (!isTrustedAndActive) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () async {
                  await ref
                      .read(userSourcesProvider.notifier)
                      .toggleTrust(widget.content.source.id, false);
                  ref.invalidate(userSourcesProvider);
                },
                icon: Icon(
                  PhosphorIcons.plus(),
                  size: 16,
                  color: Colors.white,
                ),
                label: const Text(
                  'Suivre cette source',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                    fontSize: 15,
                  ),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: colorScheme.primary,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius:
                        BorderRadius.circular(FacteurRadius.medium),
                  ),
                ),
              ),
            ),
            const SizedBox(height: FacteurSpacing.space2),
            _buildActionOption(
              context,
              icon: PhosphorIcons.prohibit(PhosphorIconsStyle.regular),
              label: 'Ne plus afficher ${widget.content.source.name}',
              isDestructive: true,
              onTap: () async {
                Navigator.pop(context);
                try {
                  final repo = ref.read(personalizationRepositoryProvider);
                  await repo.muteSource(widget.content.source.id);
                  ref.invalidate(personalizationProvider);
                  NotificationService.showInfo(
                      'Source ${widget.content.source.name} masquée');
                } catch (e) {
                  NotificationService.showError(
                      'Impossible de masquer la source');
                }
              },
              colors: colors,
            ),
            const SizedBox(height: 8),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  Navigator.of(context).pop();
                  context.pushNamed(RouteNames.sources);
                },
                icon: Icon(
                  PhosphorIcons.gear(),
                  size: 14,
                  color: colors.textSecondary,
                ),
                label: Text(
                  'Gérer mes sources',
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: _terracotta.withOpacity(0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
              border:
                  Border.all(color: _terracotta.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: _terracotta,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'Suivie',
                              style: textTheme.labelMedium?.copyWith(
                                color: _terracotta,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              '/',
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.textTertiary,
                              ),
                            ),
                            const SizedBox(width: 6),
                            GestureDetector(
                              onTap: () async {
                                Navigator.pop(context);
                                try {
                                  await ref
                                      .read(userSourcesProvider.notifier)
                                      .toggleTrust(
                                          widget.content.source.id, true);
                                  NotificationService.showInfo(
                                    '${widget.content.source.name} retirée de vos sources',
                                  );
                                } catch (e) {
                                  NotificationService.showError(
                                    'Impossible de retirer la source',
                                  );
                                }
                              },
                              child: Text(
                                'Ne plus suivre',
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.error,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Builder(builder: (context) {
                      final algoProfile = ref.watch(algorithmProfileProvider).valueOrNull;
                      final sourceId = widget.content.source.id;
                      final sourceUsage = algoProfile?.sourceAffinities[sourceId];
                      return PrioritySlider(
                        currentMultiplier: currentMultiplier,
                        onChanged: (multiplier) {
                          ref
                              .read(userSourcesProvider.notifier)
                              .updateWeight(
                                widget.content.source.id,
                                multiplier,
                              );
                        },
                        usageWeight: sourceUsage,
                      );
                    }),
                  ],
                ),
                Divider(
                  color: _terracotta.withOpacity(0.15),
                  height: 1,
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isSubscribed
                          ? PhosphorIcons.crown(PhosphorIconsStyle.fill)
                          : PhosphorIcons.crown(
                              PhosphorIconsStyle.regular),
                      size: 18,
                      color: isSubscribed
                          ? colorScheme.primary
                          : colors.textSecondary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "J'ai un abonnement payant",
                        style: textTheme.bodyMedium?.copyWith(
                          color: colors.textPrimary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    Switch.adaptive(
                      value: isSubscribed,
                      onChanged: (value) {
                        ref
                            .read(userSourcesProvider.notifier)
                            .toggleSubscription(
                              widget.content.source.id,
                              isSubscribed,
                            );
                      },
                      activeTrackColor: colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                Navigator.of(context).pop();
                context.pushNamed(RouteNames.sources);
              },
              icon: Icon(
                PhosphorIcons.gear(),
                size: 14,
                color: colors.textSecondary,
              ),
              label: Text(
                'Gérer mes sources',
                style: textTheme.labelMedium?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
        ],
      );
    });
  }

  // ── Entities content (ported from ArticleEntitiesSheet) ──

  Widget _buildEntitiesContent({
    required List<UserTopicProfile> topics,
    required FacteurColors colors,
    required TextTheme textTheme,
  }) {
    final perso = ref.watch(personalizationProvider).valueOrNull;
    final mutedTopics = perso?.mutedTopics ?? {};

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: widget.content.entities.map((entity) {
        final isEntityFollowed = topics.any(
          (t) =>
              t.canonicalName?.toLowerCase() == entity.text.toLowerCase(),
        );
        final isMuted = mutedTopics.contains(entity.text.toLowerCase());

        return Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Row(
            children: [
              Expanded(
                child: Opacity(
                  opacity: isMuted ? 0.5 : 1.0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        entity.text,
                        style: textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (entity.label.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: colors.textTertiary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            getEntityTypeLabel(entity.label),
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textTertiary,
                              fontSize: 10,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
              if (isMuted)
                // Muted state: show unmute button
                GestureDetector(
                  onTap: () async {
                    final repo = ref.read(personalizationRepositoryProvider);
                    try {
                      await repo.unmuteTopic(entity.text.toLowerCase());
                      ref.invalidate(personalizationProvider);
                    } catch (_) {}
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.textTertiary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                          size: 14,
                          color: colors.textTertiary,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Masqué',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textTertiary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else ...[
                // Mute button
                GestureDetector(
                  onTap: () async {
                    final repo = ref.read(personalizationRepositoryProvider);
                    try {
                      await repo.muteTopic(entity.text.toLowerCase());
                      ref.invalidate(personalizationProvider);
                    } catch (_) {}
                  },
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 6, vertical: 4),
                    child: Icon(
                      PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                      size: 16,
                      color: colors.textTertiary,
                    ),
                  ),
                ),
                // Follow / Followed indicator
                if (isEntityFollowed)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: _terracotta.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          PhosphorIcons.check(PhosphorIconsStyle.bold),
                          size: 14,
                          color: _terracotta,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'Suivi',
                          style: textTheme.labelSmall?.copyWith(
                            color: _terracotta,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  )
                else
                  TextButton.icon(
                    onPressed: () {
                      ref
                          .read(customTopicsProvider.notifier)
                          .followEntity(entity.text, entity.label);
                    },
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    icon: Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.bold),
                      size: 14,
                      color: _terracotta,
                    ),
                    label: Text(
                      'Suivre',
                      style: textTheme.labelSmall?.copyWith(
                        color: _terracotta,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Shared helpers ──

  /// Builds a collapsible section header.
  Widget _buildSectionHeader(
    BuildContext context, {
    IconData? icon,
    Color? iconColor,
    String? title,
    Widget? titleWidget,
    String? subtitle,
    Widget? trailing,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, color: iconColor ?? colors.textPrimary, size: 24),
                const SizedBox(width: 12),
              ],
              if (titleWidget != null)
                Expanded(child: titleWidget)
              else
                Expanded(
                  child: Text(
                    title ?? '',
                    style: icon != null
                        ? TextStyle(
                            color: colors.textPrimary,
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          )
                        : TextStyle(
                            color: colors.textSecondary,
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                  ),
                ),
              if (trailing != null) ...[
                trailing,
                const SizedBox(width: 8),
              ],
              Icon(
                isExpanded
                    ? PhosphorIcons.caretUp(PhosphorIconsStyle.bold)
                    : PhosphorIcons.caretDown(PhosphorIconsStyle.bold),
                size: 16,
                color: colors.textTertiary,
              ),
            ],
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle,
              style: textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                letterSpacing: 1.0,
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Builds the breakdown list, limited to 3 items with "Voir plus..." toggle.
  List<Widget> _buildBreakdownList(
      RecommendationReason reason, FacteurColors colors) {
    final items = reason.breakdown;
    final displayItems = _breakdownShowAll ? items : items.take(3).toList();

    return [
      ...displayItems.map((contribution) => Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(
                  contribution.isPositive
                      ? PhosphorIcons.trendUp(PhosphorIconsStyle.bold)
                      : PhosphorIcons.trendDown(PhosphorIconsStyle.bold),
                  color:
                      contribution.isPositive ? colors.success : colors.error,
                  size: 16,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    contribution.label,
                    style: TextStyle(
                      color: colors.textSecondary,
                      fontSize: 15,
                    ),
                  ),
                ),
                Text(
                  '${contribution.points > 0 ? '+' : ''}${contribution.points.toInt()}',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          )),
      if (!_breakdownShowAll && items.length > 3)
        GestureDetector(
          onTap: () => setState(() => _breakdownShowAll = true),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Voir plus\u2026',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
        ),
    ];
  }

  /// Builds an action option row.
  Widget _buildActionOption(
    BuildContext context, {
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    required FacteurColors colors,
    bool isDestructive = false,
  }) {
    final color = isDestructive ? colors.error : colors.textPrimary;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        child: Row(
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 16),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 16,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
