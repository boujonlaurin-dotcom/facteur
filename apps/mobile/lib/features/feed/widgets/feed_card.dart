import 'dart:async';
import 'dart:math' as math;

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/utils/html_utils.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/utils/article_title_layout.dart';
import 'package:facteur/features/feed/widgets/reading_badge.dart';
import 'package:facteur/widgets/design/facteur_card.dart';
import 'package:facteur/widgets/design/facteur_image.dart';
import 'package:facteur/widgets/design/facteur_thumbnail.dart';
import 'package:facteur/widgets/design/video_play_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

class FeedCard extends StatefulWidget {
  final Content content;
  final VoidCallback? onTap;
  final GestureLongPressStartCallback? onLongPressStart;
  final GestureLongPressMoveUpdateCallback? onLongPressMoveUpdate;
  final GestureLongPressEndCallback? onLongPressEnd;
  final VoidCallback? onSave;
  final VoidCallback? onSaveLongPress;
  final VoidCallback? onLike;
  final VoidCallback? onNotInterested;
  final VoidCallback? onReportNotSerene;
  final bool isSerene;
  final VoidCallback? onSourceTap; // Epic 12: tap source name/logo → detail
  final VoidCallback? onSourceLongPress; // Long-press → ArticleSheet (source section)
  final Widget? topicChipWidget;
  // DEADCODE (ClusterChip feature temporairement masquée)
  // final Widget? clusterChipWidget;
  final bool isSaved;
  final bool isLiked;
  final bool isFollowedSource;
  final bool isSourceSubscribed;
  final bool hasActiveFilter; // Feed fallback: filtre thème/topic/entité actif
  final VoidCallback? onFollowSource; // Feed fallback: suivre la source
  final Color? backgroundColor;
  final List<BoxShadow>? boxShadow;
  final String? editorialBadgeLabel;
  final bool expandContent;
  final bool alwaysShowDescription;
  final VoidCallback? onImageError;
  final double? descriptionFontSize;
  /// Max lines for the article title. Defaults to 3 — feed cards keep the
  /// tight, scannable layout. Digest singleton cards override to 5 so
  /// long titles can breathe on the "closure" moment of the app.
  final int titleMaxLines;
  final bool denseLayout;
  /// Optional GlobalKey attached to the first long-pressable badge (topic
  /// chip preferred, source badge fallback). Used by `NudgeHost` to position
  /// a spotlight for `feed_badge_longpress`. Pass only from the first feed
  /// card on screen.
  final GlobalKey? badgeAnchorKey;
  /// Optional GlobalKey attached to the card outer. Used by `NudgeHost` for
  /// the `feed_preview_longpress` spotlight.
  final GlobalKey? cardAnchorKey;

  const FeedCard({
    super.key,
    required this.content,
    this.onTap,
    this.onLongPressStart,
    this.onLongPressMoveUpdate,
    this.onLongPressEnd,
    this.onSave,
    this.onSaveLongPress,
    this.onLike,
    this.onNotInterested,
    this.onReportNotSerene,
    this.isSerene = false,
    this.onSourceTap,
    this.onSourceLongPress,
    this.topicChipWidget,
    // this.clusterChipWidget,
    this.isSaved = false,
    this.isLiked = false,
    this.isFollowedSource = false,
    this.isSourceSubscribed = false,
    this.hasActiveFilter = false,
    this.onFollowSource,
    this.backgroundColor,
    this.boxShadow,
    this.editorialBadgeLabel,
    this.expandContent = false,
    this.alwaysShowDescription = false,
    this.onImageError,
    this.descriptionFontSize,
    this.titleMaxLines = 3,
    this.denseLayout = false,
    this.badgeAnchorKey,
    this.cardAnchorKey,
  });

  @override
  State<FeedCard> createState() => _FeedCardState();
}

class _FeedCardState extends State<FeedCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pressController;
  late final Animation<double> _pressScale;

  @override
  void initState() {
    super.initState();
    _pressController = AnimationController(
      vsync: this,
      duration: FacteurDurations.fast,
      reverseDuration: FacteurDurations.medium,
    );
    _pressScale = Tween<double>(begin: 1.0, end: 0.98).animate(
      CurvedAnimation(parent: _pressController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _pressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    final isConsumed = widget.content.status == ContentStatus.consumed;
    final isVideo = widget.content.contentType == ContentType.youtube || widget.content.contentType == ContentType.video;

    final hasBeenRead = isConsumed || widget.content.readingProgress > 0;
    final card = Opacity(
      opacity: hasBeenRead ? 0.6 : 1.0,
      child: Stack(
        fit: widget.expandContent ? StackFit.expand : StackFit.loose,
        children: [
          // ScaleTransition wraps the ENTIRE card so the whole thing shrinks
          // uniformly (no white border gap between image+body and footer).
          ScaleTransition(
            scale: _pressScale,
            child: FacteurCard(
              backgroundColor: widget.backgroundColor,
              boxShadow: widget.boxShadow,
              padding: EdgeInsets.zero,
              borderRadius: FacteurRadius.small,
              child: Column(
                mainAxisSize: widget.expandContent ? MainAxisSize.max : MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Tappable area: image + body (isolated from footer buttons)
                  GestureDetector(
                    onTapDown: (_) => _pressController.forward(),
                    onTapUp: (_) => _pressController.reverse(),
                    onTapCancel: () => _pressController.reverse(),
                    onTap: widget.onTap != null
                        ? () async {
                            await HapticFeedback.mediumImpact();
                            widget.onTap?.call();
                          }
                        : null,
                    onLongPressStart: widget.onLongPressStart != null
                        ? (details) async {
                            await HapticFeedback.mediumImpact();
                            widget.onLongPressStart?.call(details);
                          }
                        : null,
                    onLongPressMoveUpdate: widget.onLongPressMoveUpdate,
                    onLongPressEnd: widget.onLongPressEnd != null
                        ? (details) {
                            _pressController.reverse();
                            widget.onLongPressEnd?.call(details);
                          }
                        : null,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Red accent line for video cards
                        if (isVideo)
                          Container(
                            height: 3,
                            color: const Color(0xFFFF0000),
                          ),

                        // 1. Image (Header)
                        FacteurThumbnail(
                          imageUrl: widget.content.thumbnailUrl,
                          borderRadius: isVideo
                              ? BorderRadius.zero
                              : const BorderRadius.vertical(
                                  top: Radius.circular(FacteurRadius.small)),
                          onError: widget.onImageError,
                          overlay: isVideo ? const VideoPlayOverlay() : null,
                          durationLabel: isVideo && widget.content.durationSeconds != null
                              ? _formatDuration(widget.content.durationSeconds!)
                              : null,
                          isVideo: isVideo,
                        ),

                        // 2. Body (Title + Meta)
                        _buildBody(context, colors, textTheme),
                      ],
                    ),
                  ),

                // 3. Footer (Source + Actions) — outside tap area
                Container(
                  decoration: BoxDecoration(
                    color: colors.backgroundSecondary.withOpacity(0.3),
                    border: Border(
                      top: BorderSide(
                        color: colors.textSecondary.withOpacity(0.05),
                        width: 0.5,
                      ),
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 3,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            // Source Logo + Name (tappable for source detail — Epic 12)
                            Flexible(
                            child: _FooterBadgeNudge(
                              // Une seule balise pulse par carte. Si la carte
                              // n'a pas de topic chip, c'est forcément la
                              // source. Sinon, parité du hashCode.
                              enabled: widget.topicChipWidget == null ||
                                  widget.content.id.hashCode.isEven,
                              child: KeyedSubtree(
                                // Fallback anchor for feed_badge_longpress when
                                // the card has no topic chip.
                                key: widget.topicChipWidget == null
                                    ? widget.badgeAnchorKey
                                    : null,
                                child: GestureDetector(
                              onTap: widget.onSourceTap,
                              onLongPress: widget.onSourceLongPress,
                              behavior: HitTestBehavior.opaque,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 3),
                                decoration: BoxDecoration(
                                  color: Colors.transparent,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (widget.content.source.logoUrl != null &&
                                        widget.content.source.logoUrl!.isNotEmpty) ...[
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: FacteurImage(
                                          imageUrl: widget.content.source.logoUrl!,
                                          width: 14,
                                          height: 14,
                                          fit: BoxFit.cover,
                                          errorWidget: (context) =>
                                              _buildSourcePlaceholder(colors),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                    ] else ...[
                                      _buildSourcePlaceholder(colors),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        widget.content.source.name,
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colors.textSecondary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 11,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            ), // KeyedSubtree
                            ), // _FooterBadgeNudge
                            ),

                            // Source suivie badge OR discovery follow CTA
                            if (widget.isFollowedSource) ...[
                              const SizedBox(width: 4),
                              Icon(
                                PhosphorIcons.star(),
                                size: 10,
                                color: colors.textTertiary,
                              ),
                            ] else if (widget.hasActiveFilter && widget.onFollowSource != null) ...[
                              const SizedBox(width: 6),
                              GestureDetector(
                                onTap: widget.onFollowSource,
                                behavior: HitTestBehavior.opaque,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 7, vertical: 3),
                                  decoration: BoxDecoration(
                                    color: Color.lerp(colors.backgroundSecondary,
                                        Colors.black, 0.008),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        'Suivre',
                                        style: textTheme.labelSmall?.copyWith(
                                          color: colors.textTertiary,
                                          fontWeight: FontWeight.w500,
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(
                                        PhosphorIcons.plus(),
                                        size: 11,
                                        color: colors.textTertiary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],

                            // Récence
                            const SizedBox(width: FacteurSpacing.space2),
                            Icon(
                              PhosphorIcons.clock(),
                              size: 11,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              timeago
                                  .format(widget.content.publishedAt,
                                      locale: 'fr_short')
                                  .replaceAll('il y a ', ''),
                              style: textTheme.labelSmall?.copyWith(
                                color: colors.textSecondary,
                                fontSize: 10,
                              ),
                            ),

                            // Paywall badge (green "Abonné" if subscribed, yellow "Payant" otherwise)
                            if (widget.content.isPaid) ...[
                              const SizedBox(width: FacteurSpacing.space2),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 2),
                                decoration: BoxDecoration(
                                  color: widget.isSourceSubscribed
                                      ? colors.success.withOpacity(0.15)
                                      : colors.warning.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      widget.isSourceSubscribed
                                          ? PhosphorIcons.crown(
                                              PhosphorIconsStyle.fill)
                                          : PhosphorIcons.lock(
                                              PhosphorIconsStyle.fill),
                                      size: 9,
                                      color: widget.isSourceSubscribed
                                          ? colors.success
                                          : colors.warning,
                                    ),
                                    const SizedBox(width: 3),
                                    Text(
                                      widget.isSourceSubscribed
                                          ? 'Abonné'
                                          : 'Payant',
                                      style: TextStyle(
                                        color: widget.isSourceSubscribed
                                            ? colors.success
                                            : colors.warning,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 9,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],

                            // Editorial badge (digest only) — truncates before source name
                            if (widget.editorialBadgeLabel != null) ...[
                              const SizedBox(width: FacteurSpacing.space2),
                              Flexible(
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 5, vertical: 2),
                                  decoration: BoxDecoration(
                                    color:
                                        colors.textSecondary.withOpacity(0.14),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: colors.textTertiary.withOpacity(0.20),
                                      width: 0.5,
                                    ),
                                  ),
                                  child: Text(
                                    widget.editorialBadgeLabel!,
                                    style: TextStyle(
                                      color: colors.textSecondary,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 10,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ),

                      // Actions (Like, Save, NotInterested, Personalize).
                      // Capped at 40% of screen width so topic tag grows into
                      // available space but remains first to truncate when the
                      // row gets crowded (Flexible on topic handles the ellipsis).
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          maxWidth: MediaQuery.of(context).size.width * 0.4,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Save button (tap = save/unsave, long press = collection picker)
                            if (widget.onSave != null)
                              GestureDetector(
                                onTap: widget.onSave,
                                onLongPress: widget.onSaveLongPress,
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  child: Icon(
                                    widget.isSaved
                                        ? PhosphorIcons.bookmarkSimple(
                                            PhosphorIconsStyle.fill)
                                        : PhosphorIcons.bookmarkSimple(),
                                    size: 18,
                                    color: widget.isSaved
                                        ? colors.primary
                                        : colors.textSecondary,
                                  ),
                                ),
                              ),

                            // TODO(beta-post): "Pas serein" report button masqué pour Beta 1.0.
                            // Le tap ne se déclenche pas de manière fiable — cause non identifiée
                            // malgré plusieurs tentatives (InkWell, GestureDetector, restructuration
                            // du widget tree). À investiguer après le lancement Beta.
                            // Ticket : bug-report-not-serene-feed

                            // Topic chip (replaces NotInterested when provided)
                            if (widget.topicChipWidget != null)
                              Flexible(
                                child: _FooterBadgeNudge(
                                  enabled: widget.content.id.hashCode.isOdd,
                                  child: KeyedSubtree(
                                    // Nudge anchor attaches to topic chip when
                                    // present (priority target for
                                    // feed_badge_longpress spotlight).
                                    key: widget.topicChipWidget != null
                                        ? widget.badgeAnchorKey
                                        : null,
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 4),
                                      child: widget.topicChipWidget!,
                                    ),
                                  ),
                                ),
                              )
                            else if (widget.onNotInterested != null)
                              InkWell(
                                onTap: widget.onNotInterested,
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(5),
                                  child: Icon(
                                    PhosphorIcons.eyeSlash(),
                                    size: 18,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),

                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // DEADCODE (ClusterChip feature temporairement masquée, l'espace occupé n'étant pas justifié actuellement)
                // if (widget.clusterChipWidget != null) widget.clusterChipWidget!,
              ],
            ),
          ),
          ), // ScaleTransition
          if (widget.content.hasNote)
            Positioned(
              top: 12,
              left: 12,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.primary.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.pencilLine(PhosphorIconsStyle.fill),
                      size: 11,
                      color: Colors.white,
                    ),
                    const SizedBox(width: 3),
                    const Text(
                      'Article annoté',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          if (isConsumed || widget.content.readingProgress > 0)
            Positioned(
              top: 12,
              right: 12,
              child: ReadingBadge(content: widget.content),
            ),
        ],
      ),
    );
    if (widget.cardAnchorKey != null) {
      return KeyedSubtree(key: widget.cardAnchorKey!, child: card);
    }
    return card;
  }

  Widget _buildBody(
      BuildContext context, FacteurColors colors, TextTheme textTheme) {
    final hasDescription =
        widget.content.description != null && widget.content.description!.isNotEmpty;
    final hasImage = widget.content.thumbnailUrl != null &&
        widget.content.thumbnailUrl!.isNotEmpty;
    final effectiveTitleMaxLines =
        hasImage ? math.min(3, widget.titleMaxLines) : widget.titleMaxLines;

    final bodyContent = Padding(
      padding: EdgeInsets.symmetric(
        horizontal: FacteurSpacing.space3,
        vertical: widget.denseLayout ? FacteurSpacing.space2 : FacteurSpacing.space3,
      ),
      child: Column(
        mainAxisSize: widget.expandContent ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final estimatedTitleLines = ArticleTitleLayout.estimateTitleLines(
                title: widget.content.title,
                availableWidth: constraints.maxWidth,
                hasImage: hasImage,
              );
              final int descMaxLines;
              if (widget.expandContent) {
                descMaxLines = 8;
              } else if (widget.alwaysShowDescription) {
                descMaxLines = ArticleTitleLayout.descriptionMaxLinesForCarousel(
                  estimatedTitleLines: estimatedTitleLines,
                  hasImage: hasImage,
                  hasDescription: hasDescription,
                );
              } else {
                descMaxLines = ArticleTitleLayout.descriptionMaxLines(
                  estimatedTitleLines: estimatedTitleLines,
                  hasImage: hasImage,
                  hasDescription: hasDescription,
                );
              }
              final showDescription = widget.expandContent
                  ? hasDescription
                  : descMaxLines > 0;

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    widget.content.title,
                    style: textTheme.displaySmall?.copyWith(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      height: 1.2,
                    ),
                    maxLines:
                        widget.expandContent ? null : effectiveTitleMaxLines,
                    overflow:
                        widget.expandContent ? null : TextOverflow.ellipsis,
                  ),
                  if (showDescription) ...[
                    const SizedBox(height: FacteurSpacing.space2),
                    Text(
                      stripHtml(widget.content.description!),
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary.withOpacity(0.85),
                        height: 1.3,
                        fontSize: widget.descriptionFontSize,
                      ),
                      maxLines:
                          widget.expandContent ? 8 : descMaxLines,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              );
            },
          ),
          const SizedBox(height: FacteurSpacing.space2),
          // Métadonnées (Type • Durée)
          Row(
            children: [
              _buildTypeIcon(context, widget.content.contentType),
              const SizedBox(width: FacteurSpacing.space2),
              if (widget.content.durationSeconds != null)
                Text(
                  _formatDuration(widget.content.durationSeconds!),
                  style: textTheme.labelSmall?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500),
                ),
            ],
          ),
        ],
      ),
    );

    if (widget.expandContent) {
      return Expanded(child: bodyContent);
    }
    return bodyContent;
  }

  Widget _buildSourcePlaceholder(FacteurColors colors) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          widget.content.source.name.isNotEmpty
              ? widget.content.source.name.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.bold,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  Widget _buildTypeIcon(BuildContext context, ContentType type) {
    final colors = context.facteurColors;
    IconData icon;

    switch (type) {
      case ContentType.video:
      case ContentType.youtube:
        // Play overlay + red accent line suffice as video indicator
        return const SizedBox.shrink();
      case ContentType.audio:
        icon = PhosphorIcons.headphones(PhosphorIconsStyle.fill);
        break;
      default:
        // No icon for articles to reduce clutter
        return const SizedBox.shrink();
    }

    return Icon(icon, size: 14, color: colors.textSecondary);
  }

  /*
  String _getThemeDisplayName(String themeCode) {
    switch (themeCode.toLowerCase()) {
      case 'tech':
        return 'TECH & FUTUR';
      case 'geopolitics':
        return 'GÉOPOLITIQUE';
      case 'economy':
        return 'ÉCONOMIE';
      case 'society_climate':
        return 'SOCIÉTÉ & CLIMAT';
      case 'culture_ideas':
        return 'CULTURE & IDÉES';
      default:
        return themeCode.toUpperCase();
    }
  }
  */

  String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }
}

/// Subtle periodic nudge on footer badges to hint at long-press.
/// Plays a tiny scale pulse (~2%) at random intervals (8–15 s).
class _FooterBadgeNudge extends StatefulWidget {
  final Widget child;
  final bool enabled;

  const _FooterBadgeNudge({required this.child, this.enabled = true});

  @override
  State<_FooterBadgeNudge> createState() => _FooterBadgeNudgeState();
}

class _FooterBadgeNudgeState extends State<_FooterBadgeNudge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  final math.Random _rng = math.Random();
  Timer? _timer;
  bool _firstPopFired = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    );
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        _scheduleNext();
      }
    });
    if (widget.enabled) _scheduleNext();
  }

  @override
  void didUpdateWidget(_FooterBadgeNudge oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled && !oldWidget.enabled) {
      _scheduleNext();
    } else if (!widget.enabled && oldWidget.enabled) {
      _timer?.cancel();
      _controller.value = 0;
    }
  }

  void _scheduleNext() {
    // 1er pop rapide pour être découvrable, puis cadence rare (20–35 s).
    final delayMs = !_firstPopFired
        ? 2500 + _rng.nextInt(2000)
        : 20000 + _rng.nextInt(15000);
    _firstPopFired = true;
    _timer?.cancel();
    _timer = Timer(Duration(milliseconds: delayMs), () {
      if (mounted) _controller.forward(from: 0);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final t = _controller.value;
        // Pulsation ease-in-out smooth : grossissement bien visible sans
        // coloration. Pic à scale 1.12 puis retour.
        final pulse = math.sin(t * math.pi);
        final eased = Curves.easeInOutSine.transform(pulse.clamp(0.0, 1.0));
        final scale = 1.0 + 0.12 * eased;
        return Transform.scale(scale: scale, child: child);
      },
      child: widget.child,
    );
  }
}
