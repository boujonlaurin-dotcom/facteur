import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../../config/theme.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/feed_card.dart';
import '../../feed/widgets/dismiss_banner.dart';
import '../../saved/widgets/collection_picker_sheet.dart';
import '../../sources/models/source_model.dart';
import '../models/digest_models.dart';
import '../models/community_carousel_model.dart';
import 'actu_decalee_block.dart';
import 'closure_block.dart';
import 'community_carousel_section.dart';
import 'coup_de_coeur_block.dart';
import 'pepite_block.dart';
import 'quote_block.dart';
import 'section_divider.dart';
import 'serein_toggle_chip.dart';
import 'topic_section.dart';
import 'transition_text.dart';

/// Digest Briefing Section.
/// Compact iOS-style segmented control sits top-right in the header.
class DigestBriefingSection extends StatefulWidget {
  final List<DigestItem> items;
  final List<DigestTopic>? topics;
  final DigestResponse? digest;
  final void Function(DigestItem) onItemTap;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onNotInterested;
  final void Function(DigestItem)? onReportNotSerene;
  final void Function(DigestItem)? onSwipeDismiss;
  final void Function(String sourceId)? onMuteSource;
  final void Function(String topic)? onMuteTopic;
  final void Function(String sourceId)? onSourceTap;
  final bool isSerein;
  final bool usesEditorial;
  final PepiteResponse? pepite;
  final CoupDeCoeurResponse? coupDeCoeur;
  final PepiteResponse? actuDecalee;
  final String? headerText;
  final String? closureText;
  final String? ctaText;
  final int processedCount;
  final int dailyGoal;
  final List<CommunityCarouselItem> communityCarousel;
  final void Function(CommunityCarouselItem)? onCommunityArticleTap;

  const DigestBriefingSection({
    super.key,
    required this.items,
    this.topics,
    this.digest,
    required this.onItemTap,
    this.onSave,
    this.onLike,
    this.onNotInterested,
    this.onReportNotSerene,
    this.onSwipeDismiss,
    this.onMuteSource,
    this.onMuteTopic,
    this.onSourceTap,
    this.isSerein = false,
    this.usesEditorial = false,
    this.pepite,
    this.coupDeCoeur,
    this.actuDecalee,
    this.headerText,
    this.closureText,
    this.ctaText,
    this.processedCount = 0,
    this.dailyGoal = 5,
    this.communityCarousel = const [],
    this.onCommunityArticleTap,
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

    return Padding(
      padding: const EdgeInsets.only(top: 12, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header: title (left) | serein toggle (right)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    "L'Essentiel du jour",
                    style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontSize: 19,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                const SereinToggleChip(),
              ],
            ),
          ),
          // Compact progress counter below title
          if (widget.dailyGoal > 0)
            Padding(
              padding: const EdgeInsets.only(left: 14, top: 6),
              child: _buildCompactCounter(colors),
            ),
          const SizedBox(height: 10),
          // Content area with crossfade on serein toggle
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: KeyedSubtree(
              key: ValueKey(widget.isSerein),
              child: widget.usesEditorial && _usesTopics
                  ? _buildEditorialLayout()
                  : _usesTopics
                      ? _buildTopicsLayout()
                      : _buildFlatLayout(context),
            ),
          ),
        ],
      ),
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
      separatorBuilder: (context, index) => const SizedBox(height: 2),
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
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => TopicSection(
        topic: widget.topics![i],
        totalTopics: widget.topics!.length,
        onArticleTap: widget.onItemTap,
        onSave: widget.onSave,
        onNotInterested: widget.onNotInterested,
        onSourceTap: widget.onSourceTap,
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

  /// Editorial layout: prose + DigestCards + pépite + coup de cœur + closure
  Widget _buildCompactCounter(FacteurColors colors) {
    final processed = widget.processedCount;
    final denominator = widget.dailyGoal;
    final isComplete = processed >= denominator;
    final color = isComplete ? colors.success : colors.primary;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        ...List.generate(denominator, (i) {
          final isDone = i < processed;
          return Container(
            width: 8,
            height: 2,
            margin: EdgeInsets.only(right: i < denominator - 1 ? 2 : 0),
            decoration: BoxDecoration(
              color: isDone
                  ? (isComplete ? colors.success : color)
                  : colors.textTertiary.withOpacity(0.25),
              borderRadius: BorderRadius.circular(1.25),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildEditorialLayout() {
    final isSerene = widget.isSerein;
    final sections = <Widget>[];

    // Quote block first in serein mode — sets the tone for the reading
    if (isSerene && widget.digest?.quote != null) {
      sections.add(QuoteBlock(quote: widget.digest!.quote!));
    }

    // Topics with intro text, editorial DigestCards, and transition text
    for (int i = 0; i < widget.topics!.length; i++) {
      final topic = widget.topics![i];

      // Topic section with editorial cards (intro handled inside TopicSection)
      sections.add(
        TopicSection(
          topic: topic,
          totalTopics: widget.topics!.length,
          editorialMode: true,
          isSerene: isSerene,
          onArticleTap: widget.onItemTap,
          onSave: widget.onSave,
          onNotInterested: widget.onNotInterested,
          onReportNotSerene: widget.onReportNotSerene,
          onSourceTap: widget.onSourceTap,
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

      // Transition text between topics (not after last one)
      if (topic.transitionText != null && i < widget.topics!.length - 1) {
        sections.add(TransitionText(text: topic.transitionText!));
      }
    }

    // Section divider before special picks
    if (widget.pepite != null || widget.coupDeCoeur != null || widget.actuDecalee != null) {
      sections.add(const SectionDivider());
    }

    // Pépite block
    if (widget.pepite != null) {
      sections.add(
        PepiteBlock(
          pepite: widget.pepite!,
          isSerene: isSerene,
          onTap: widget.onItemTap,
          onSave: widget.onSave,
          onNotInterested: widget.onNotInterested,
          onReportNotSerene: widget.onReportNotSerene,
          onSourceTap: widget.onSourceTap,
        ),
      );
    }

    // Coup de cœur block
    if (widget.coupDeCoeur != null) {
      sections.add(
        CoupDeCoeurBlock(
          coupDeCoeur: widget.coupDeCoeur!,
          isSerene: isSerene,
          onTap: widget.onItemTap,
          onSave: widget.onSave,
          onNotInterested: widget.onNotInterested,
          onReportNotSerene: widget.onReportNotSerene,
          onSourceTap: widget.onSourceTap,
        ),
      );
    }

    // Actu décalée block (serein mode only)
    if (widget.actuDecalee != null) {
      sections.add(
        ActuDecaleeBlock(
          actuDecalee: widget.actuDecalee!,
          onTap: widget.onItemTap,
          onSave: widget.onSave,
          onNotInterested: widget.onNotInterested,
          onReportNotSerene: widget.onReportNotSerene,
          onSourceTap: widget.onSourceTap,
        ),
      );
    }

    // Community 🌻 carousel (if items available)
    if (widget.communityCarousel.isNotEmpty) {
      sections.add(const SectionDivider());
      sections.add(
        CommunityCarouselSection(
          items: widget.communityCarousel,
          onArticleTap: (item) {
            widget.onCommunityArticleTap?.call(item);
          },
        ),
      );
    }

    // Closure block (always shown with fallback)
    sections.add(
      ClosureBlock(
        closureText: widget.closureText ?? 'Bonne lecture !',
        ctaText: widget.ctaText,
      ),
    );

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: sections.length,
      separatorBuilder: (_, __) => const SizedBox(height: 14),
      itemBuilder: (_, i) => sections[i],
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Rank label above the card
        Padding(
          padding: const EdgeInsets.only(left: 4, bottom: 4),
          child: Row(
            children: [
              Text(
                rank.toString().padLeft(2, '0'),
                style: TextStyle(
                  color: colors.primary.withOpacity(0.6),
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                  letterSpacing: 0.5,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                '\u2014',
                style: TextStyle(
                  color: labelColor,
                  fontWeight: FontWeight.w500,
                  fontSize: 12,
                ),
              ),
              const SizedBox(width: 6),
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
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Opacity(
            opacity: item.isRead || item.isDismissed ? 0.6 : 1.0,
            child: FeedCard(
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 8, offset: const Offset(0, 2))],
              content: _convertToContent(item),
              descriptionFontSize: 15,
              titleMaxLines: 5,
              denseLayout: true,
              onTap: () => widget.onItemTap(item),
              onSourceTap: widget.onSourceTap != null && item.source?.id != null
                  ? () => widget.onSourceTap!(item.source!.id!)
                  : null,
              onSourceLongPress: () => TopicChip.showArticleSheet(
                  context, _convertToContent(item),
                  initialSection: ArticleSheetSection.source),
              onLongPressStart: (_) => ArticlePreviewOverlay.show(
                context,
                _convertToContent(item),
              ),
              onLongPressMoveUpdate: (details) =>
                  ArticlePreviewOverlay.updateScroll(
                details.localOffsetFromOrigin.dy,
              ),
              onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
              onSave: widget.onSave != null ? () => widget.onSave!(item) : null,
              onSaveLongPress: () =>
                  CollectionPickerSheet.show(context, item.contentId),
              onNotInterested: widget.onNotInterested != null
                  ? () => widget.onNotInterested!(item)
                  : null,
              isSerene: widget.isSerein,
              onReportNotSerene: widget.onReportNotSerene != null
                  ? () => widget.onReportNotSerene!(item)
                  : null,
              isSaved: item.isSaved,
              topicChipWidget: TopicChip(
                content: _convertToContent(item),
              ),
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
      topics: item.topics,
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
