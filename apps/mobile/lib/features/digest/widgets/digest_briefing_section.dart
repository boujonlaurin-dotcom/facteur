import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import '../models/digest_mode.dart';
import 'digest_mode_tab_selector.dart';
import 'digest_personalization_sheet.dart';

/// Digest Briefing Section with premium design.
/// Container smoothly animates its background color, border, and glow
/// based on the active DigestMode using TweenAnimationBuilder.
///
/// Compact iOS-style segmented control sits top-right in the header.
class DigestBriefingSection extends StatefulWidget {
  final List<DigestItem> items;
  final int completionThreshold;
  final void Function(DigestItem) onItemTap;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final DigestMode mode;
  final bool isRegenerating;
  final ValueChanged<DigestMode>? onModeChanged;

  const DigestBriefingSection({
    super.key,
    required this.items,
    this.completionThreshold = 5,
    required this.onItemTap,
    this.onSave,
    this.onNotInterested,
    this.mode = DigestMode.pourVous,
    this.isRegenerating = false,
    this.onModeChanged,
  });

  @override
  State<DigestBriefingSection> createState() => _DigestBriefingSectionState();
}

class _DigestBriefingSectionState extends State<DigestBriefingSection> {
  /// Le sous-titre n'apparaît qu'après un changement de mode, puis disparaît après 4s.
  bool _showSubtitle = false;
  Timer? _subtitleTimer;

  @override
  void didUpdateWidget(DigestBriefingSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mode != widget.mode) {
      _subtitleTimer?.cancel();
      setState(() => _showSubtitle = true);
      _subtitleTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) setState(() => _showSubtitle = false);
      });
    }
  }

  @override
  void dispose() {
    _subtitleTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modeColor = widget.mode.effectiveColor(colors.primary);

    // Calculate reading time (average 2 min per article if null)
    final totalSeconds = widget.items.fold<int>(0, (sum, item) {
      return sum + (item.durationSeconds ?? 120);
    });
    final totalMinutes = (totalSeconds / 60).ceil();

    // Resolve gradient colors based on brightness
    final gradStart =
        isDark ? widget.mode.gradientStart : widget.mode.lightGradientStart;
    final gradEnd =
        isDark ? widget.mode.gradientEnd : widget.mode.lightGradientEnd;

    // TweenAnimationBuilder for smooth gradient transitions between modes.
    // Only `end` is set so changes animate from current value → new.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: gradStart),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, animatedBaseColor, child) {
        final baseColor = animatedBaseColor ?? gradStart;
        return Container(
          margin: const EdgeInsets.only(top: 16, bottom: 12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                baseColor,
                Color.lerp(baseColor, gradEnd, 0.7)!,
              ],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : Colors.black.withValues(alpha: 0.10),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color:
                    Colors.black.withValues(alpha: isDark ? 0.25 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: title+progress (left) | selector+subtitle (right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: title + reading time
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                "L'Essentiel du jour",
                                style: Theme.of(context)
                                    .textTheme
                                    .displaySmall
                                    ?.copyWith(
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                      letterSpacing: -0.5,
                                      color: isDark
                                          ? Colors.white
                                          : colors.textPrimary,
                                    ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 10),
                            _buildSegmentedProgressBar(colors),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            Icon(
                              PhosphorIcons.clock(
                                  PhosphorIconsStyle.regular),
                              size: 14,
                              color: isDark
                                  ? Colors.white.withValues(alpha: 0.5)
                                  : colors.textSecondary,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              '$totalMinutes min de lecture',
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: isDark
                                        ? Colors.white
                                            .withValues(alpha: 0.5)
                                        : colors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Right: segmented control + subtitle (apparaît puis disparaît)
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (widget.onModeChanged != null)
                        DigestModeSegmentedControl(
                          selectedMode: widget.mode,
                          isRegenerating: widget.isRegenerating,
                          onModeChanged: (newMode) {
                            widget.onModeChanged!(newMode);
                          },
                        ),
                      const SizedBox(height: 6),
                      // Sous-titre visible uniquement après changement de mode
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 300),
                        child: _showSubtitle
                            ? Text(
                                widget.mode.subtitle,
                                key: ValueKey(widget.mode.key),
                                style: TextStyle(
                                  color: modeColor.withValues(alpha: 0.85),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  fontFamily: 'DM Sans',
                                  letterSpacing: 0.1,
                                ),
                                textAlign: TextAlign.right,
                              )
                            : const SizedBox.shrink(
                                key: ValueKey('empty_subtitle'),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // List of articles
              ListView.separated(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: widget.items.length,
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final item = widget.items[index];
                  return _buildRankedCard(context, item, index + 1, isDark);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSegmentedProgressBar(FacteurColors colors) {
    final processedCount = widget.items
        .where((item) => item.isRead || item.isDismissed || item.isSaved)
        .length;
    final isDone = processedCount >= widget.completionThreshold;
    final totalCount = widget.items.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$processedCount/${widget.completionThreshold}',
          style: TextStyle(
            color: isDone ? colors.success : colors.primary,
            fontWeight: FontWeight.bold,
            fontSize: 12,
          ),
        ),
        const SizedBox(width: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(totalCount, (index) {
            final isFilled = index < processedCount;
            final isThresholdBoundary =
                widget.completionThreshold < totalCount &&
                    index == widget.completionThreshold - 1;
            return Container(
              width: 8,
              height: 4,
              margin: EdgeInsets.only(
                right: isThresholdBoundary ? 6 : 2,
              ),
              decoration: BoxDecoration(
                color: isFilled
                    ? (isDone ? colors.success : colors.primary)
                    : colors.backgroundSecondary,
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildRankedCard(
      BuildContext context, DigestItem item, int rank, bool isDark) {
    final colors = context.facteurColors;
    final labelColor =
        isDark ? Colors.white.withValues(alpha: 0.5) : colors.textSecondary;
    final dotColor = isDark
        ? Colors.white.withValues(alpha: 0.2)
        : colors.textTertiary.withValues(alpha: 0.4);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rank label above the card
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 6),
          child: Row(
            children: [
              Text(
                'N\u00B0$rank',
                style: TextStyle(
                  color: colors.primary.withValues(alpha: isDark ? 0.9 : 1.0),
                  fontWeight: FontWeight.w900,
                  fontSize: 13,
                  letterSpacing: 1.0,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                width: 4,
                height: 4,
                decoration: BoxDecoration(
                  color: dotColor,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _simplifyReason(item.reason),
                  style: TextStyle(
                    color: labelColor,
                    fontWeight: FontWeight.w600,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              // Info button for algorithm transparency
              if (item.recommendationReason != null)
                InkWell(
                  onTap: () => _showReasoningSheet(context, item),
                  borderRadius: BorderRadius.circular(12),
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      PhosphorIcons.info(PhosphorIconsStyle.regular),
                      size: 16,
                      color: colors.primary,
                    ),
                  ),
                ),
              if (item.isRead)
                Icon(
                  PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.success,
                ),
            ],
          ),
        ),
        // The card with save/not interested actions and long-press for reasoning
        GestureDetector(
          onLongPress: item.recommendationReason != null
              ? () {
                  HapticFeedback.mediumImpact();
                  _showReasoningSheet(context, item);
                }
              : null,
          behavior: HitTestBehavior.translucent,
          child: Opacity(
            opacity: item.isRead || item.isDismissed ? 0.6 : 1.0,
            child: FeedCard(
              content: _convertToContent(item),
              onTap: () => widget.onItemTap(item),
              onSave: widget.onSave != null ? () => widget.onSave!(item) : null,
              onNotInterested: widget.onNotInterested != null
                  ? () => widget.onNotInterested!(item)
                  : null,
              isSaved: item.isSaved,
            ),
          ),
        ),
      ],
    );
  }

  /// Converts DigestItem to Content for FeedCard compatibility
  Content _convertToContent(DigestItem item) {
    return Content(
      id: item.contentId,
      title: item.title,
      url: item.url,
      thumbnailUrl: item.thumbnailUrl,
      description: item.description,
      contentType: item.contentType,
      durationSeconds: item.durationSeconds,
      publishedAt: item.publishedAt ?? DateTime.now(),
      source: Source(
        id: item.source?.id ?? item.contentId,
        name: item.source?.name ?? 'Source inconnue',
        type: _mapSourceType(item.contentType),
        logoUrl: item.source?.logoUrl,
        theme: item.source?.theme,
      ),
    );
  }

  SourceType _mapSourceType(ContentType type) {
    switch (type) {
      case ContentType.video:
        return SourceType.video;
      case ContentType.audio:
        return SourceType.podcast;
      case ContentType.youtube:
        return SourceType.youtube;
      default:
        return SourceType.article;
    }
  }

  /// Clean up reason strings for display.
  /// New format "Thème : X" is kept. Legacy formats are simplified.
  static String _simplifyReason(String reason) {
    var r = reason;
    // Strip " (+N pts)" suffix from legacy data
    r = r.replaceAll(RegExp(r'\s*\(\+\d+\s*pts?\)'), '');
    // Keep "Thème : X" as-is, strip detail after ":" for other patterns
    if (r.contains(':') && !r.startsWith('Thème')) {
      r = r.split(':').first.trim();
    }
    // Strip " depuis ..." from legacy "Sélectionné pour vous depuis X"
    r = r.replaceAll(RegExp(r'\s+depuis\s+.*', caseSensitive: false), '');
    return r.trim().toUpperCase();
  }

  /// Show the personalization sheet with scoring breakdown
  void _showReasoningSheet(BuildContext context, DigestItem item) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => DigestPersonalizationSheet(item: item),
    );
  }
}
