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

/// Digest Briefing Section with premium design for 7 articles.
/// Container adapts its gradient, border color, glow, and subtitle
/// based on the active DigestMode.
///
/// Features a segmented control selector above the header,
/// stronger mode-adaptive gradients, and card glow effects.
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

    return Column(
      children: [
        // Segmented control selector above the card
        if (onModeChanged != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  child: DigestModeSegmentedControl(
                    selectedMode: mode,
                    isRegenerating: isRegenerating,
                    onModeChanged: (newMode) {
                      if (onModeChanged != null) {
                        onModeChanged!(newMode);
                      }
                    },
                  ),
                ),
                const SizedBox(height: 8),
                // Mode subtitle — lisible, bonne taille, bonne opacité
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: Text(
                    mode.subtitle,
                    key: ValueKey(mode.key),
                    style: TextStyle(
                      color: modeColor.withValues(alpha: 0.85),
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      fontFamily: 'DM Sans',
                      letterSpacing: 0.1,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ),
          ),

        // Main card container with mode-adaptive gradient and glow
        AnimatedContainer(
          duration: const Duration(milliseconds: 400),
          curve: Curves.easeOutCubic,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: isDark
                  ? [
                      mode.gradientStart,
                      mode.gradientEnd,
                      mode.backgroundColor.withValues(alpha: 0.0),
                    ]
                  : [
                      colors.backgroundSecondary,
                      colors.backgroundPrimary,
                      colors.backgroundPrimary.withValues(alpha: 0.0),
                    ],
              stops: const [0.0, 0.7, 1.0],
            ),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(24),
              topRight: Radius.circular(24),
              bottomLeft: Radius.circular(8),
              bottomRight: Radius.circular(8),
            ),
            border: Border.all(
              color: isDark
                  ? modeColor.withValues(alpha: 0.25)
                  : modeColor.withValues(alpha: 0.12),
              width: 1,
            ),
            boxShadow: isDark
                ? [
                    // Glow effect dans la couleur du mode
                    BoxShadow(
                      color: mode.cardGlowColor,
                      blurRadius: 30,
                      spreadRadius: -5,
                      offset: const Offset(0, -4),
                    ),
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ]
                : [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.05),
                      blurRadius: 15,
                      offset: const Offset(0, 8),
                    ),
                  ],
          ),
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: title + progress (left) | reading time (right)
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  // Title + progress
                  Expanded(
                    child: Row(
                      children: [
                        Text(
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
                        ),
                        const SizedBox(width: 10),
                        _buildSegmentedProgressBar(colors),
                      ],
                    ),
                  ),
                  // Reading time
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        PhosphorIcons.clock(PhosphorIconsStyle.regular),
                        size: 14,
                        color: isDark
                            ? Colors.white.withValues(alpha: 0.5)
                            : colors.textSecondary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '$totalMinutes min',
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: isDark
                                      ? Colors.white.withValues(alpha: 0.5)
                                      : colors.textSecondary,
                                  fontWeight: FontWeight.w500,
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
                separatorBuilder: (context, index) =>
                    const SizedBox(height: 7),
                itemBuilder: (context, index) {
                  final item = items[index];
                  return _buildRankedCard(context, item, index + 1, isDark);
                },
              ),
            ],
          ),
        ),
      ],
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
