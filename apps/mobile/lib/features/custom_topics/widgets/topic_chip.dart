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
import '../providers/custom_topics_provider.dart';
import 'topic_priority_slider.dart';
import '../../../widgets/design/priority_slider.dart';
import '../../sources/providers/sources_providers.dart';

/// Terracotta accent color for custom topics.
const Color _terracotta = Color(0xFFE07A5F);

/// Discreet topic tag in the feed card footer.
///
/// Renders as subtle inline text embedded in the footer row.
/// [isFollowed] must be provided by the parent to avoid per-chip provider watches.
/// Tap opens the unified article sheet.
class TopicChip extends StatelessWidget {
  final Content content;
  final bool isFollowed;

  const TopicChip({
    super.key,
    required this.content,
    this.isFollowed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (content.topics.isEmpty) return const SizedBox.shrink();

    final topicSlug = content.topics.first;
    final topicLabel = getTopicLabel(topicSlug);
    final colors = context.facteurColors;

    final icon = isFollowed
        ? PhosphorIcons.check(PhosphorIconsStyle.bold)
        : PhosphorIcons.plus(PhosphorIconsStyle.bold);

    return GestureDetector(
      onTap: () => showArticleSheet(context, content),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Color.lerp(colors.backgroundSecondary, Colors.black, 0.008)!,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ConstrainedBox(
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
            const SizedBox(width: 4),
            Icon(
              icon,
              size: 12,
              color: colors.textTertiary,
            ),
          ],
        ),
      ),
    );
  }

  /// Opens the unified article sheet with blur backdrop.
  static void showArticleSheet(BuildContext context, Content content) {
    final topicSlug = content.topics.first;
    final topicLabel = getTopicLabel(topicSlug);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      barrierColor: Colors.black.withValues(alpha: 0.5),
      builder: (ctx) => BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: ArticleSheet(
          content: content,
          topicSlug: topicSlug,
          topicLabel: topicLabel,
        ),
      ),
    );
  }
}

/// Unified modal sheet combining topic controls + article personalization.
///
/// Section 1: Topic follow/priority controls (always visible)
/// Section 2: "Pourquoi cet article ?" (collapsible breakdown)
/// Section 3: "Personnaliser mon flux" (collapsible actions)
class ArticleSheet extends ConsumerStatefulWidget {
  final Content content;
  final String topicSlug;
  final String topicLabel;

  const ArticleSheet({
    super.key,
    required this.content,
    required this.topicSlug,
    required this.topicLabel,
  });

  @override
  ConsumerState<ArticleSheet> createState() => _ArticleSheetState();
}

class _ArticleSheetState extends ConsumerState<ArticleSheet> {
  late bool _breakdownExpanded;
  bool _breakdownShowAll = false;
  bool _personalizeExpanded = true;

  @override
  void initState() {
    super.initState();
    final reason = widget.content.recommendationReason;
    _breakdownExpanded = reason != null && reason.breakdown.isNotEmpty;
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
    final parentEmoji =
        parentLabel != null ? getMacroThemeEmoji(parentLabel) : '';

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
                    color: colors.textTertiary.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: FacteurSpacing.space3),

              // ── Section 1: Topic (always visible) ──
              RichText(
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
              if (parentLabel != null) ...[
                const SizedBox(height: 4),
                Text(
                  '${parentEmoji.isNotEmpty ? '$parentEmoji ' : ''}$parentLabel',
                  style: textTheme.labelSmall?.copyWith(
                    color: colors.textTertiary,
                    letterSpacing: 1.0,
                  ),
                ),
              ],
              const SizedBox(height: FacteurSpacing.space4),

              // Follow / Priority control
              if (isFollowed && matchedTopic != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: _terracotta.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(FacteurRadius.medium),
                    border: Border.all(
                      color: _terracotta.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Left: dot + "Suivi"
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
                          ],
                        ),
                      ),
                      const Spacer(),
                      // Right: preference label + slider
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: Text(
                          'Préférence :',
                          style: textTheme.labelSmall?.copyWith(
                            color: colors.textSecondary,
                            height: 1.0,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      TopicPrioritySlider(
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
                      ),
                    ],
                  ),
                )
              else
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
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.medium),
                      ),
                    ),
                  ),
                ),

              if (!isFollowed) ...[
                const SizedBox(height: FacteurSpacing.space2),
                Center(
                  child: Text(
                    'Recevez plus d\'articles sur ${widget.topicLabel}',
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textTertiary,
                    ),
                  ),
                ),
              ],

              // "Gérer mes intérêts" CTA
              const SizedBox(height: 8),
              Center(
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  onPressed: () {
                    Navigator.of(context).pop();
                    context.pushNamed(RouteNames.myInterests);
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

              // ── Section Source ──
              if (widget.content.source.name.isNotEmpty) ...[
                const SizedBox(height: FacteurSpacing.space2),
                Divider(color: colors.textTertiary.withValues(alpha: 0.2)),
                const SizedBox(height: FacteurSpacing.space3),

                // Source header: logo + name + theme
                Row(
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
                const SizedBox(height: FacteurSpacing.space3),

                // Source card (slider + mute inside)
                Builder(builder: (context) {
                  final sourcesAsync = ref.watch(userSourcesProvider);
                  final currentMultiplier = sourcesAsync.whenOrNull(
                        data: (sources) {
                          final match = sources
                              .where(
                                  (s) => s.id == widget.content.source.id)
                              .firstOrNull;
                          return match?.priorityMultiplier;
                        },
                      ) ??
                      1.0;
                  final isTrustedAndActive = sourcesAsync.whenOrNull(
                        data: (sources) {
                          final match = sources
                              .where(
                                  (s) => s.id == widget.content.source.id)
                              .firstOrNull;
                          return match?.isTrusted == true &&
                              match?.isMuted != true;
                        },
                      ) ??
                      false;

                  if (!isTrustedAndActive) {
                    // Not trusted: standalone mute button
                    return _buildActionOption(
                      context,
                      icon: PhosphorIcons.prohibit(
                          PhosphorIconsStyle.regular),
                      label:
                          'Ne plus afficher ${widget.content.source.name}',
                      isDestructive: true,
                      onTap: () async {
                        Navigator.pop(context);
                        try {
                          await ref
                              .read(feedProvider.notifier)
                              .muteSource(widget.content);
                          NotificationService.showInfo(
                              'Source ${widget.content.source.name} masquée');
                        } catch (e) {
                          NotificationService.showError(
                              'Impossible de masquer la source');
                        }
                      },
                      colors: colors,
                    );
                  }

                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _terracotta.withValues(alpha: 0.08),
                      borderRadius:
                          BorderRadius.circular(FacteurRadius.medium),
                      border: Border.all(
                        color: _terracotta.withValues(alpha: 0.2),
                      ),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        // Left: dot + "Suivie" / mute link
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
                                  style:
                                      textTheme.labelMedium?.copyWith(
                                    color: _terracotta,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  '/',
                                  style:
                                      textTheme.labelSmall?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                GestureDetector(
                                  onTap: () async {
                                    Navigator.pop(context);
                                    try {
                                      await ref
                                          .read(feedProvider.notifier)
                                          .muteSource(widget.content);
                                      NotificationService.showInfo(
                                        'Source ${widget.content.source.name} masquée',
                                      );
                                    } catch (e) {
                                      NotificationService.showError(
                                        'Impossible de masquer la source',
                                      );
                                    }
                                  },
                                  child: Text(
                                    'Masquer',
                                    style: textTheme.labelSmall
                                        ?.copyWith(
                                      color: colors.error,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        // Right: preference label + slider
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            'Préférence :',
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.0,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        PrioritySlider(
                          currentMultiplier: currentMultiplier,
                          onChanged: (multiplier) {
                            ref
                                .read(userSourcesProvider.notifier)
                                .updateWeight(
                                  widget.content.source.id,
                                  multiplier,
                                );
                          },
                          labels: const [
                            'Reduit',
                            'Normal',
                            'Favori',
                          ],
                        ),
                      ],
                    ),
                  );
                }),

                // CTA: "Gérer mes sources"
                const SizedBox(height: 8),
                Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 4,
                      ),
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

              // ── Section 2: "Pourquoi cet article ?" ──
              if (reason != null && reason.breakdown.isNotEmpty) ...[
                const SizedBox(height: FacteurSpacing.space2),
                Divider(color: colors.textTertiary.withValues(alpha: 0.2)),
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
                            color: colors.primary.withValues(alpha: 0.1),
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

              // ── Section 3: "Personnaliser mon flux" ──
              const SizedBox(height: FacteurSpacing.space2),
              Divider(color: colors.textTertiary.withValues(alpha: 0.2)),
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
                if (widget.content.topics.isNotEmpty)
                  _buildActionOption(
                    context,
                    icon: PhosphorIcons.thumbsDown(PhosphorIconsStyle.regular),
                    label: "Je n'aime pas le sujet",
                    isDestructive: true,
                    onTap: () async {
                      Navigator.pop(context);
                      try {
                        for (final topicSlug in widget.content.topics) {
                          await ref
                              .read(feedProvider.notifier)
                              .muteTopic(topicSlug);
                        }
                        NotificationService.showInfo('Sujets masqués');
                      } catch (e) {
                        NotificationService.showError(
                            'Impossible de masquer les sujets');
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

  /// Builds a collapsible section header.
  Widget _buildSectionHeader(
    BuildContext context, {
    IconData? icon,
    Color? iconColor,
    required String title,
    Widget? trailing,
    required bool isExpanded,
    required VoidCallback onToggle,
  }) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onToggle,
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, color: iconColor ?? colors.textPrimary, size: 24),
            const SizedBox(width: 12),
          ],
          Expanded(
            child: Text(
              title,
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
