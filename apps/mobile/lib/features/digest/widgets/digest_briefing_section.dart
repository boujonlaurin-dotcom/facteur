import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import '../models/digest_mode.dart';
import 'digest_personalization_sheet.dart';

/// Digest Briefing Section with premium design for 7 articles.
/// Container adapts its gradient, border color, and subtitle
/// based on the active DigestMode.
///
/// Mode badges (emoji) are positioned top-right of the header,
/// progress counter is near the title on the left.
class DigestBriefingSection extends StatelessWidget {
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
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final colors = context.facteurColors;

    // Calculate reading time (average 2 min per article if null)
    final totalSeconds = items.fold<int>(0, (sum, item) {
      return sum + (item.durationSeconds ?? 120);
    });
    final totalMinutes = (totalSeconds / 60).ceil();

    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Mode-adaptive colors for container
    final modeColor = mode.effectiveColor(colors.primary);
    final containerBgColors = isDark
        ? [mode.gradientStart, mode.gradientEnd]
        : [colors.backgroundSecondary, colors.backgroundPrimary];

    final headerTextColor = isDark ? Colors.white : colors.textPrimary;
    final subheaderTextColor =
        isDark ? Colors.white.withValues(alpha: 0.6) : colors.textSecondary;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      margin: const EdgeInsets.only(top: 16, bottom: 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: containerBgColors,
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(
          color: isDark
              ? modeColor.withValues(alpha: 0.3)
              : modeColor.withValues(alpha: 0.15),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.05),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: title + progress (left) | mode emoji badges (right)
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + progress on the left
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Title row with inline progress
                    Row(
                      children: [
                        Text(
                          "L'Essentiel",
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: headerTextColor,
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
                          PhosphorIcons.clock(PhosphorIconsStyle.regular),
                          size: 14,
                          color: subheaderTextColor,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '$totalMinutes min de lecture',
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: subheaderTextColor,
                                    fontWeight: FontWeight.w500,
                                  ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Emoji mode badges + subtitle on the right
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  // Emoji badges row
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: DigestMode.values.map((m) => _ModeBadge(
                          mode: m,
                          isSelected: m == mode,
                          primaryColor: colors.primary,
                          dimColor: colors.textTertiary,
                          onTap: isRegenerating || onModeChanged == null
                              ? null
                              : () {
                                  HapticFeedback.lightImpact();
                                  onModeChanged!(m);
                                },
                        )).toList(),
                  ),
                  // Mode subtitle aligned under badges
                  const SizedBox(height: 6),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 200),
                    child: Text(
                      mode.subtitle,
                      key: ValueKey(mode.key),
                      style: TextStyle(
                        color: modeColor.withValues(alpha: 0.7),
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        fontStyle: FontStyle.italic,
                        fontFamily: 'DM Sans',
                      ),
                      textAlign: TextAlign.right,
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
            itemCount: items.length,
            separatorBuilder: (context, index) => const SizedBox(height: 7),
            itemBuilder: (context, index) {
              final item = items[index];
              return _buildRankedCard(context, item, index + 1, isDark);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSegmentedProgressBar(FacteurColors colors) {
    final processedCount = items
        .where((item) => item.isRead || item.isDismissed || item.isSaved)
        .length;
    final isDone = processedCount >= completionThreshold;
    final totalCount = items.length;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$processedCount/$completionThreshold',
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
                completionThreshold < totalCount &&
                    index == completionThreshold - 1;
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
              onTap: () => onItemTap(item),
              onSave: onSave != null ? () => onSave!(item) : null,
              onNotInterested:
                  onNotInterested != null ? () => onNotInterested!(item) : null,
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

/// Emoji badge for a digest mode, displayed top-right of the header.
/// Premium design with subtle glow when selected.
class _ModeBadge extends StatelessWidget {
  final DigestMode mode;
  final bool isSelected;
  final Color primaryColor;
  final Color dimColor;
  final VoidCallback? onTap;

  const _ModeBadge({
    required this.mode,
    required this.isSelected,
    required this.primaryColor,
    required this.dimColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final modeColor = mode.effectiveColor(primaryColor);

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutCubic,
        margin: const EdgeInsets.only(left: 6),
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: isSelected
              ? modeColor.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? modeColor.withValues(alpha: 0.5)
                : dimColor.withValues(alpha: 0.15),
            width: isSelected ? 1.5 : 1.0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: modeColor.withValues(alpha: 0.25),
                    blurRadius: 10,
                    spreadRadius: 0,
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Text(
            mode.emoji,
            style: TextStyle(
              fontSize: isSelected ? 18 : 16,
            ),
          ),
        ),
      ),
    );
  }
}
