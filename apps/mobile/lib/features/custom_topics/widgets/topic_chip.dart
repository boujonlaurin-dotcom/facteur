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
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        decoration: BoxDecoration(
          color: colors.textTertiary.withOpacity(0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          topicLabel,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textTertiary,
                fontWeight: FontWeight.w500,
                fontSize: 11,
              ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }

  /// Opens the unified article sheet with blur backdrop.
  ///
  /// [highlightInitialSection] triggers a pulse-glow on the primary control
  /// (slider or main CTA) of [initialSection] — used when the sheet is opened
  /// from the post-swipe feedback banner to hint the user toward the slider
  /// they should adjust.
  static Future<void> showArticleSheet(
    BuildContext context,
    Content content, {
    ArticleSheetSection initialSection = ArticleSheetSection.topic,
    bool highlightInitialSection = false,
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
          highlightInitialSection: highlightInitialSection,
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

  /// When true, the slider/CTA of [initialSection] pulses for ~2s after the
  /// sheet opens. Used to hint the user toward the control they should
  /// adjust when entering via the post-swipe feedback banner.
  final bool highlightInitialSection;

  const ArticleSheet({
    super.key,
    required this.content,
    required this.topicSlug,
    required this.topicLabel,
    this.initialSection = ArticleSheetSection.topic,
    this.highlightInitialSection = false,
  });

  @override
  ConsumerState<ArticleSheet> createState() => _ArticleSheetState();
}

class _ArticleSheetState extends ConsumerState<ArticleSheet> {
  bool _breakdownShowAll = false;

  @override
  void initState() {
    super.initState();
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

              // ── Groupes 1 & 2: SUJETS / SOURCE (order depends on entry point) ──
              ..._buildSujetsAndSource(
                isFollowed: isFollowed,
                matchedTopic: matchedTopic,
                colorScheme: colorScheme,
                colors: colors,
                textTheme: textTheme,
                parentLabel: parentLabel,
                topics: topics,
              ),

              // ── Groupe 3: RECOMMANDATION ──
              if (reason != null && reason.breakdown.isNotEmpty) ...[
              const SizedBox(height: FacteurSpacing.space3),
              Divider(color: colors.textTertiary.withOpacity(0.2)),
              const SizedBox(height: FacteurSpacing.space3),
              Row(
                children: [
                  Text(
                    'RECOMMANDATION',
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.textTertiary,
                      letterSpacing: 1.2,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (reason != null && reason.scoreTotal > 0) ...[
                    const Spacer(),
                    Container(
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
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),
              ..._buildBreakdownList(reason!, colors),
              const SizedBox(height: FacteurSpacing.space2),
              ],

              const SizedBox(height: FacteurSpacing.space4),
            ],
          ),
        ),
      ),
    );
  }

  // ── Ordered SUJETS + SOURCE sections ──

  List<Widget> _buildSujetsAndSource({
    required bool isFollowed,
    required UserTopicProfile? matchedTopic,
    required ColorScheme colorScheme,
    required FacteurColors colors,
    required TextTheme textTheme,
    required String? parentLabel,
    required List<UserTopicProfile> topics,
  }) {
    final hasSujets =
        widget.topicSlug.isNotEmpty || widget.content.entities.isNotEmpty;
    final hasSource = widget.content.source.name.isNotEmpty;

    final divider = [
      const SizedBox(height: FacteurSpacing.space3),
      Divider(color: colors.textTertiary.withOpacity(0.2)),
      const SizedBox(height: FacteurSpacing.space3),
    ];

    final sujetsBlock = [
      if (hasSujets) ...[
        Text(
          'SUJETS',
          style: textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: FacteurSpacing.space2),
        _buildTopicContent(
          isFollowed: isFollowed,
          matchedTopic: matchedTopic,
          colorScheme: colorScheme,
          colors: colors,
          textTheme: textTheme,
          parentLabel: parentLabel,
          shouldHighlight: widget.highlightInitialSection &&
              widget.initialSection == ArticleSheetSection.topic,
          topics: topics,
        ),
      ],
    ];

    final sourceBlock = [
      if (hasSource) ...[
        Text(
          'SOURCE',
          style: textTheme.labelSmall?.copyWith(
            color: colors.textTertiary,
            letterSpacing: 1.2,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: FacteurSpacing.space2),
        _buildSourceContent(
          colorScheme: colorScheme,
          colors: colors,
          textTheme: textTheme,
          shouldHighlight: widget.highlightInitialSection &&
              widget.initialSection == ArticleSheetSection.source,
        ),
      ],
    ];

    final sourceFirst =
        widget.initialSection == ArticleSheetSection.source;

    if (sourceFirst) {
      return [
        ...sourceBlock,
        if (hasSujets && hasSource) ...divider,
        ...sujetsBlock,
      ];
    } else {
      return [
        ...sujetsBlock,
        if (hasSujets && hasSource) ...divider,
        ...sourceBlock,
      ];
    }
  }

  // ── Topic + Entities content (SUJETS group) ──

  Widget _buildTopicContent({
    required bool isFollowed,
    required UserTopicProfile? matchedTopic,
    required ColorScheme colorScheme,
    required FacteurColors colors,
    required TextTheme textTheme,
    required String? parentLabel,
    required List<UserTopicProfile> topics,
    bool shouldHighlight = false,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Topic header: topicLabel on top, parentLabel below, Suivi right-aligned ──
        if (widget.topicSlug.isNotEmpty) ...[
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.topicLabel,
                      style: textTheme.displaySmall?.copyWith(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (parentLabel != null) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: colors.textTertiary.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${getMacroThemeEmoji(parentLabel)} $parentLabel',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 12),
              if (isFollowed && matchedTopic != null)
                Row(
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
            ],
          ),
          const SizedBox(height: FacteurSpacing.space2),

          // ── Priority rectangle (followed) or Follow button (not followed) ──
          if (isFollowed && matchedTopic != null)
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: _terracotta.withOpacity(0.08),
                borderRadius: BorderRadius.circular(FacteurRadius.medium),
                border: Border.all(color: _terracotta.withOpacity(0.2)),
              ),
              child: Builder(builder: (context) {
                final algoProfile =
                    ref.watch(algorithmProfileProvider).valueOrNull;
                final topicSlug = matchedTopic.slugParent;
                final topicUsage = algoProfile != null &&
                        algoProfile.subtopicWeights.containsKey(topicSlug)
                    ? algoProfile.normalizeWeight(
                        algoProfile.subtopicWeights[topicSlug]!)
                    : null;
                return _PulseHighlight(
                  active: shouldHighlight,
                  child: TopicPrioritySlider(
                    currentMultiplier: matchedTopic.priorityMultiplier,
                    fillWidth: true,
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
                            await client
                                .post('/users/subtopics/$topicSlug/reset');
                            ref.invalidate(algorithmProfileProvider);
                          }
                        : null,
                  ),
                );
              }),
            )
          else ...[
            _PulseHighlight(
              active: shouldHighlight,
              child: SizedBox(
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
                        final msg = (detail is Map &&
                                detail['detail'] is String)
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
                  icon: Icon(PhosphorIcons.plus(), size: 16, color: Colors.white),
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
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.medium),
                    ),
                  ),
                ),
              ),
            ),
            Center(
              child: TextButton.icon(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  foregroundColor: colors.error,
                ),
                onPressed: () async {
                  try {
                    final repo = ref.read(personalizationRepositoryProvider);
                    await repo.muteTopic(widget.topicSlug);
                    NotificationService.showInfo('Sujet masqué');
                    if (!mounted) return;
                    ref.invalidate(personalizationProvider);
                    Navigator.pop(context);
                  } catch (e) {
                    NotificationService.showError(
                      'Impossible de masquer le sujet',
                    );
                  }
                },
                icon: Icon(
                  PhosphorIcons.eyeSlash(PhosphorIconsStyle.regular),
                  size: 16,
                  color: colors.error,
                ),
                label: Text(
                  'Masquer ce sujet',
                  style: textTheme.labelMedium?.copyWith(
                    color: colors.error,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ],

        // ── Entities (always visible, no header) ──
        if (widget.content.entities.isNotEmpty) ...[
          const SizedBox(height: FacteurSpacing.space4),
          _buildEntitiesContent(
              topics: topics, colors: colors, textTheme: textTheme),
        ],

        // ── Gérer mes intérêts at bottom of SUJETS ──
        if (widget.topicSlug.isNotEmpty) ...[
          const SizedBox(height: 4),
          Center(
            child: TextButton.icon(
              style: TextButton.styleFrom(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
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
      ],
    );
  }

  // ── Source content (MÉDIA group) ──

  Widget _buildSourceContent({
    required ColorScheme colorScheme,
    required FacteurColors colors,
    required TextTheme textTheme,
    bool shouldHighlight = false,
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

      // ── Source header: logo + name/theme + Suivie/Suivre right-aligned ──
      Widget sourceHeader = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
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
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(width: 10),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.content.source.name,
                  style: textTheme.displaySmall?.copyWith(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
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
          const SizedBox(width: 12),
          if (isTrustedAndActive)
            Row(
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
                          .toggleTrust(widget.content.source.id, true);
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
        ],
      );

      final Widget manageButton = Center(
        child: TextButton.icon(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () {
            Navigator.of(context).pop();
            context.pushNamed(RouteNames.sources);
          },
          icon: Icon(PhosphorIcons.gear(), size: 14, color: colors.textSecondary),
          label: Text(
            'Gérer mes sources',
            style: textTheme.labelMedium?.copyWith(color: colors.textSecondary),
          ),
        ),
      );

      if (!isTrustedAndActive) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            sourceHeader,
            const SizedBox(height: FacteurSpacing.space2),
            _PulseHighlight(
              active: shouldHighlight,
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () async {
                    await ref
                        .read(userSourcesProvider.notifier)
                        .toggleTrust(widget.content.source.id, false);
                    ref.invalidate(userSourcesProvider);
                  },
                  icon: Icon(PhosphorIcons.plus(), size: 16, color: Colors.white),
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
                      borderRadius: BorderRadius.circular(FacteurRadius.medium),
                    ),
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
            manageButton,
          ],
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          sourceHeader,
          const SizedBox(height: FacteurSpacing.space2),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _terracotta.withOpacity(0.08),
              borderRadius: BorderRadius.circular(FacteurRadius.medium),
              border: Border.all(color: _terracotta.withOpacity(0.2)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Builder(builder: (context) {
                  final algoProfile =
                      ref.watch(algorithmProfileProvider).valueOrNull;
                  final sourceId = widget.content.source.id;
                  final sourceUsage = algoProfile?.sourceAffinities[sourceId];
                  return _PulseHighlight(
                    active: shouldHighlight,
                    child: PrioritySlider(
                      currentMultiplier: currentMultiplier,
                      fillWidth: true,
                      onChanged: (multiplier) {
                        ref
                            .read(userSourcesProvider.notifier)
                            .updateWeight(widget.content.source.id, multiplier);
                      },
                      usageWeight: sourceUsage,
                    ),
                  );
                }),
                Divider(color: _terracotta.withOpacity(0.15), height: 1),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Icon(
                      isSubscribed
                          ? PhosphorIcons.crown(PhosphorIconsStyle.fill)
                          : PhosphorIcons.crown(PhosphorIconsStyle.regular),
                      size: 18,
                      color:
                          isSubscribed ? colorScheme.primary : colors.textSecondary,
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
                                widget.content.source.id, isSubscribed);
                      },
                      activeTrackColor: colorScheme.primary,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          manageButton,
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

/// Pulse-glow highlight used to draw attention to a control inside
/// [ArticleSheet] when the sheet is opened from the post-swipe feedback
/// banner.
///
/// Renders a terracotta [BoxShadow] that fades in/out for 3 cycles of 700 ms,
/// starting 300 ms after build (so the sheet's slide-in animation finishes
/// first). When [active] is `false`, renders [child] verbatim (no shadow,
/// no animation, no rebuilds).
class _PulseHighlight extends StatefulWidget {
  final Widget child;
  final bool active;

  const _PulseHighlight({required this.child, required this.active});

  @override
  State<_PulseHighlight> createState() => _PulseHighlightState();
}

class _PulseHighlightState extends State<_PulseHighlight>
    with SingleTickerProviderStateMixin {
  static const _cycleDuration = Duration(milliseconds: 700);
  static const _startDelay = Duration(milliseconds: 300);
  static const _cycles = 3;

  late final AnimationController _ctrl;
  late final Animation<double> _glow;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _cycleDuration);
    _glow = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: 1.0)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 50,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 0.0)
            .chain(CurveTween(curve: Curves.easeIn)),
        weight: 50,
      ),
    ]).animate(_ctrl);

    if (widget.active) {
      Future.delayed(_startDelay, () {
        if (!mounted) return;
        _ctrl.repeat();
        Future.delayed(_cycleDuration * _cycles, () {
          if (!mounted) return;
          _ctrl.stop();
          _ctrl.value = 0;
        });
      });
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    return AnimatedBuilder(
      animation: _glow,
      builder: (_, child) {
        final v = _glow.value;
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            boxShadow: v > 0
                ? [
                    BoxShadow(
                      color: _terracotta.withOpacity(0.45 * v),
                      blurRadius: 16 * v,
                      spreadRadius: 2 * v,
                    ),
                  ]
                : const [],
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
