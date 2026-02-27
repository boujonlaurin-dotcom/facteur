import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../feed/widgets/swipe_to_open_card.dart';
import '../../feed/widgets/dismiss_banner.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import '../models/digest_mode.dart';
import 'digest_mode_tab_selector.dart';
import 'topic_section.dart';

/// Digest Briefing Section with premium design.
/// Container smoothly animates its background color, border, and glow
/// based on the active DigestMode using TweenAnimationBuilder.
///
/// Compact iOS-style segmented control sits top-right in the header.
class DigestBriefingSection extends StatefulWidget {
  final List<DigestItem> items;
  final List<DigestTopic>? topics;
  final void Function(DigestItem) onItemTap;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onNotInterested;
  final void Function(DigestItem)? onSwipeDismiss;
  final void Function(String sourceId)? onMuteSource;
  final void Function(String topic)? onMuteTopic;
  final DigestMode mode;
  final bool isRegenerating;

  /// Called when the user taps the disabled mode selector (navigate to settings).
  final VoidCallback? onTapModeSelector;

  const DigestBriefingSection({
    super.key,
    required this.items,
    this.topics,
    required this.onItemTap,
    this.onSave,
    this.onLike,
    this.onNotInterested,
    this.onSwipeDismiss,
    this.onMuteSource,
    this.onMuteTopic,
    this.mode = DigestMode.pourVous,
    this.isRegenerating = false,
    this.onTapModeSelector,
  });

  @override
  State<DigestBriefingSection> createState() => _DigestBriefingSectionState();
}

class _DigestBriefingSectionState extends State<DigestBriefingSection> {
  bool get _usesTopics =>
      widget.topics != null && widget.topics!.isNotEmpty;

  // --- Dismiss banner state ---
  String? _activeDismissalId;
  DigestItem? _activeDismissalItem;

  void _handleLocalSwipeDismiss(DigestItem item) {
    if (_activeDismissalId != null) {
      _resolveActiveBanner();
    }
    setState(() {
      _activeDismissalId = item.contentId;
      _activeDismissalItem = item;
    });
  }

  void _handleLocalUndo() {
    setState(() {
      _activeDismissalId = null;
      _activeDismissalItem = null;
    });
  }

  void _handleLocalAutoResolve() {
    final item = _activeDismissalItem;
    if (item != null) {
      widget.onSwipeDismiss?.call(item);
    }
    setState(() {
      _activeDismissalId = null;
      _activeDismissalItem = null;
    });
  }

  void _handleLocalMuteSource() {
    final item = _activeDismissalItem;
    if (item != null) {
      widget.onSwipeDismiss?.call(item);
      final sourceId = item.source?.id;
      if (sourceId != null && sourceId.isNotEmpty) {
        widget.onMuteSource?.call(sourceId);
      }
    }
    setState(() {
      _activeDismissalId = null;
      _activeDismissalItem = null;
    });
  }

  void _handleLocalMuteTopic(String topic) {
    final item = _activeDismissalItem;
    if (item != null) {
      widget.onSwipeDismiss?.call(item);
      widget.onMuteTopic?.call(topic);
    }
    setState(() {
      _activeDismissalId = null;
      _activeDismissalItem = null;
    });
  }

  void _resolveActiveBanner() {
    final item = _activeDismissalItem;
    if (item != null) {
      widget.onSwipeDismiss?.call(item);
    }
    _activeDismissalId = null;
    _activeDismissalItem = null;
  }

  @override
  Widget build(BuildContext context) {
    if (widget.items.isEmpty && !_usesTopics) return const SizedBox.shrink();

    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final modeColor = widget.mode.effectiveColor(colors.primary);

    // Gradient adapté au thème : dark → gradients sombres, light → gradients clairs.
    final gradStart =
        isDark ? widget.mode.gradientStart : widget.mode.lightGradientStart;
    final gradEnd =
        isDark ? widget.mode.gradientEnd : widget.mode.lightGradientEnd;

    // Couleurs internes : texte et icônes s'adaptent au fond du container.
    final textPrimary =
        isDark ? Colors.white : const Color(0xFF2C1E10);

    // TweenAnimationBuilder for smooth gradient transitions between modes.
    // Only `end` is set so changes animate from current value → new.
    return TweenAnimationBuilder<Color?>(
      tween: ColorTween(end: gradStart),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      builder: (context, animatedBaseColor, child) {
        final baseColor = animatedBaseColor ?? gradStart;
        final blendedEnd = Color.lerp(baseColor, gradEnd, 0.7)!;

        // En light mode : gradient semi-transparent pour laisser le fond
        // crème transparaître. Plus léger en haut, plus teinté en bas.
        final topColor = isDark
            ? baseColor
            : baseColor.withValues(alpha: 0.35);
        final bottomColor = isDark
            ? blendedEnd
            : blendedEnd.withValues(alpha: 0.55);

        return Container(
          margin: const EdgeInsets.only(top: 12, bottom: 8),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [topColor, bottomColor],
            ),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark
                  ? Colors.white.withValues(alpha: 0.08)
                  : baseColor.withValues(alpha: 0.25),
              width: 1,
            ),
            boxShadow: [
              BoxShadow(
                color: isDark
                    ? Colors.black.withValues(alpha: 0.25)
                    : baseColor.withValues(alpha: 0.15),
                blurRadius: isDark ? 20 : 12,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header: title+progress (left) | selector+subtitle (right)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left: title + progress bar
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "L'Essentiel du jour",
                          style: Theme.of(context)
                              .textTheme
                              .displaySmall
                              ?.copyWith(
                                fontSize: 23,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.5,
                                color: textPrimary,
                              ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        _buildSegmentedProgressBar(colors, isDark),
                      ],
                    ),
                  ),
                  // Right: segmented control (disabled) + CTA label
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      DigestModeSegmentedControl(
                        selectedMode: widget.mode,
                        disabled: true,
                        onTapDisabled: widget.onTapModeSelector,
                      ),
                      if (widget.onTapModeSelector != null) ...[
                        const SizedBox(height: 4),
                        GestureDetector(
                          onTap: widget.onTapModeSelector,
                          child: Text(
                            'Modifier',
                            style: TextStyle(
                              color: modeColor.withValues(alpha: 0.75),
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              fontFamily: 'DM Sans',
                              letterSpacing: 0.2,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
              ),
              const SizedBox(height: 10),

              // Layout branching: topics or flat
              if (_usesTopics)
                _buildTopicsLayout()
              else
                _buildFlatLayout(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSegmentedProgressBar(
      FacteurColors colors, bool isDark) {
    final int processedCount;
    final int totalCount;

    if (_usesTopics) {
      totalCount = widget.topics!.length;
      processedCount = widget.topics!.where((t) => t.isCovered).length;
    } else {
      totalCount = widget.items.length;
      processedCount = widget.items
          .where((item) => item.isRead || item.isDismissed || item.isSaved)
          .length;
    }

    final isDone = processedCount >= totalCount;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$processedCount/$totalCount',
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
            return Container(
              width: 8,
              height: 4,
              margin: EdgeInsets.only(
                right: index < totalCount - 1 ? 2 : 0,
              ),
              decoration: BoxDecoration(
                color: isFilled
                    ? (isDone ? colors.success : colors.primary)
                    : isDark
                        ? Colors.white.withValues(alpha: 0.15)
                        : Colors.black.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(2),
              ),
            );
          }),
        ),
      ],
    );
  }

  /// Flat layout: existing list of ranked cards (flat_v1 / legacy)
  Widget _buildFlatLayout(BuildContext context) {
    final visibleItems =
        widget.items.where((item) => !item.isDismissed).toList();
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: visibleItems.length,
      separatorBuilder: (context, index) => const SizedBox(height: 5),
      itemBuilder: (context, index) {
        final item = visibleItems[index];
        return _buildRankedCard(context, item, index + 1);
      },
    );
  }

  /// Topics layout: sections with horizontal article scroll (topics_v1)
  Widget _buildTopicsLayout() {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: widget.topics!.length,
      separatorBuilder: (_, __) => const SizedBox(height: 16),
      itemBuilder: (_, i) => TopicSection(
        topic: widget.topics![i],
        onArticleTap: widget.onItemTap,
        onLike: widget.onLike,
        onSave: widget.onSave,
        onNotInterested: widget.onNotInterested,
        onSwipeDismiss: widget.onSwipeDismiss != null
            ? _handleLocalSwipeDismiss
            : null,
        activeDismissalId: _activeDismissalId,
        onDismissUndo: _handleLocalUndo,
        onDismissAutoResolve: _handleLocalAutoResolve,
        onDismissMuteSource: _handleLocalMuteSource,
        onDismissMuteTopic: _handleLocalMuteTopic,
      ),
    );
  }

  Widget _buildRankedCard(
      BuildContext context, DigestItem item, int rank) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // Couleurs de label adaptées au fond du container
    final labelColor = isDark
        ? const Color(0x80FFFFFF) // white 50%
        : const Color(0x802C1E10); // dark brown 50%
    final dotColor = isDark
        ? const Color(0x33FFFFFF) // white 20%
        : const Color(0x332C1E10); // dark brown 20%

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
                  color: colors.primary.withValues(alpha: 0.9),
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
              if (item.isRead)
                Icon(
                  PhosphorIcons.checkCircle(PhosphorIconsStyle.fill),
                  size: 16,
                  color: colors.success,
                ),
            ],
          ),
        ),
        // Show dismiss banner if this card is being dismissed
        if (_activeDismissalId == item.contentId)
          AnimatedSize(
            duration: const Duration(milliseconds: 300),
            child: DismissBanner(
              content: _convertToContent(item),
              onUndo: _handleLocalUndo,
              onMuteSource: _handleLocalMuteSource,
              onMuteTopic: _handleLocalMuteTopic,
              onAutoResolve: _handleLocalAutoResolve,
            ),
          )
        else
        // The card with save/not interested actions and long-press for preview
        SwipeToOpenCard(
          onSwipeOpen: () => widget.onItemTap(item),
          onSwipeDismiss: widget.onSwipeDismiss != null
              ? () => _handleLocalSwipeDismiss(item)
              : null,
          child: Opacity(
            opacity: item.isRead || item.isDismissed ? 0.6 : 1.0,
            child: FeedCard(
              boxShadow: const [],
              content: _convertToContent(item),
              onTap: () => widget.onItemTap(item),
              onLongPressStart: (_) => ArticlePreviewOverlay.show(
                context,
                _convertToContent(item),
              ),
              onLongPressMoveUpdate: (details) =>
                  ArticlePreviewOverlay.updateScroll(
                details.localOffsetFromOrigin.dy,
              ),
              onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
              onLike: widget.onLike != null ? () => widget.onLike!(item) : null,
              isLiked: item.isLiked,
              onSave: widget.onSave != null ? () => widget.onSave!(item) : null,
              onSaveLongPress: () =>
                  CollectionPickerSheet.show(context, item.contentId),
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
      isLiked: item.isLiked,
      isSaved: item.isSaved,
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

}
