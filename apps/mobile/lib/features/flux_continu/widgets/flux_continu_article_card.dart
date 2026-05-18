import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../../config/theme.dart';
import '../../../config/topic_labels.dart';
import '../../../widgets/article_preview_modal.dart';
import '../../../widgets/design/facteur_image.dart';
import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/swipe_to_open_card.dart';
import '../../sources/models/source_model.dart';

/// Unified view-model that hides the DigestItem vs Content split from the
/// rendering layer. Both types carry the fields needed to display a Flux
/// Continu list item, but their field names diverge enough to warrant a
/// thin adapter rather than a sea of conditionals in the widget.
class FluxArticleVM {
  final String contentId;
  final String title;
  final String? thumbnailUrl;
  final String sourceName;
  final String? sourceLogoUrl;
  final String? themeLabel;
  final ContentType contentType;
  final int? durationSeconds;
  final DateTime? publishedAt;
  final bool isFollowedSource;

  const FluxArticleVM({
    required this.contentId,
    required this.title,
    required this.sourceName,
    required this.contentType,
    this.thumbnailUrl,
    this.sourceLogoUrl,
    this.themeLabel,
    this.durationSeconds,
    this.publishedAt,
    this.isFollowedSource = false,
  });

  factory FluxArticleVM.from(Object article) {
    if (article is DigestItem) {
      return FluxArticleVM(
        contentId: article.contentId,
        title: article.title,
        thumbnailUrl: article.thumbnailUrl,
        sourceName: article.source?.name ?? 'Inconnu',
        sourceLogoUrl: article.source?.logoUrl,
        themeLabel: (article.source?.theme != null &&
                article.source!.theme!.isNotEmpty)
            ? getTopicLabel(article.source!.theme!)
            : null,
        contentType: article.contentType,
        durationSeconds: article.durationSeconds,
        publishedAt: article.publishedAt,
        isFollowedSource: article.isFollowedSource,
      );
    }
    if (article is Content) {
      return FluxArticleVM(
        contentId: article.id,
        title: article.title,
        thumbnailUrl: article.thumbnailUrl,
        sourceName: article.source.name,
        sourceLogoUrl: article.source.logoUrl,
        themeLabel: article.progressionTopic,
        contentType: article.contentType,
        durationSeconds: article.durationSeconds,
        publishedAt: article.publishedAt,
        isFollowedSource: article.isFollowedSource,
      );
    }
    throw ArgumentError('Unsupported article type: ${article.runtimeType}');
  }
}

/// Article list item for the Flux Continu V1.8.
///
/// Layout per maquette V6 :
/// - 12px padding inside a 12-radius surface card, soft shadow.
/// - Head row : title (4-line ellipsis, DM Sans 15 w600) + 72×72 thumb on
///   the right (radius 10).
/// - Footer row (single-line) : source dot + name · theme pill · clock·time
///   · optional press-review trailing (Essentiel sections only).
class FluxContinuArticleCard extends StatelessWidget {
  final Object article;
  final VoidCallback? onTap;
  final VoidCallback? onSwipeDismiss;
  final bool enableSwipeHint;
  final VoidCallback? onSwipeHintComplete;
  final bool isEssentiel;
  final int pressReviewCount;
  final List<SourceMini> perspectiveSources;

  const FluxContinuArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.onSwipeDismiss,
    this.enableSwipeHint = false,
    this.onSwipeHintComplete,
    this.isEssentiel = false,
    this.pressReviewCount = 0,
    this.perspectiveSources = const [],
  });

  @override
  Widget build(BuildContext context) {
    final vm = FluxArticleVM.from(article);
    final colors = context.facteurColors;
    final hasThumb = vm.thumbnailUrl != null && vm.thumbnailUrl!.isNotEmpty;

    Widget card = Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        elevation: 0,
        child: GestureDetector(
          onLongPressStart: (_) =>
              ArticlePreviewOverlay.show(context, articleToContent(article)),
          onLongPressMoveUpdate: (details) => ArticlePreviewOverlay.updateScroll(
              details.localOffsetFromOrigin.dy),
          onLongPressEnd: (_) => ArticlePreviewOverlay.dismiss(),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Ink(
              decoration: BoxDecoration(
                color: colors.surface,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 14, 12, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            vm.title,
                            style: GoogleFonts.dmSans(
                              fontSize: 17.5,
                              fontWeight: FontWeight.w600,
                              height: 1.3,
                              letterSpacing: -0.15,
                              color: colors.textPrimary,
                            ),
                            maxLines: 5,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (hasThumb) ...[
                          const SizedBox(width: 12),
                          _Thumbnail(
                            url: vm.thumbnailUrl!,
                            isVideo: _isVideo(vm.contentType),
                            accent: colors.primary,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    _Footer(
                      vm: vm,
                      colors: colors,
                      showPressReview: isEssentiel && pressReviewCount > 0,
                      pressReviewCount: pressReviewCount,
                      perspectiveSources: perspectiveSources,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (onTap != null) {
      card = SwipeToOpenCard(
        onSwipeOpen: onTap!,
        onSwipeDismiss: onSwipeDismiss,
        enableHintAnimation: enableSwipeHint,
        onHintAnimationComplete: onSwipeHintComplete,
        child: card,
      );
    }

    return card;
  }

  bool _isVideo(ContentType type) =>
      type == ContentType.video || type == ContentType.youtube;
}

/// Adapter producing a synthetic [Content] suitable for [ArticlePreviewOverlay]
/// or [TopicChip.showArticleSheet] regardless of the source type. [DigestItem]
/// carries every field needed by the preview except the rich [Source] object —
/// a minimal [Source] is built from its [SourceMini]. Exposed as top-level so
/// the screen can reuse it when resolving an inline-feedback chip on a digest
/// lead.
Content articleToContent(Object article) {
  if (article is Content) return article;
  if (article is DigestItem) {
    final src = article.source;
    return Content(
      id: article.contentId,
      title: article.title,
      url: article.url,
      thumbnailUrl: article.thumbnailUrl,
      description: article.description,
      htmlContent: article.htmlContent,
      contentType: article.contentType,
      durationSeconds: article.durationSeconds,
      publishedAt: article.publishedAt ?? DateTime.now(),
      source: Source(
        id: src?.id ?? '',
        name: src?.name ?? 'Inconnu',
        type: SourceType.article,
        theme: src?.theme,
        logoUrl: src?.logoUrl,
      ),
      topics: article.topics,
      isPaid: article.isPaid,
      isSaved: article.isSaved,
      isLiked: article.isLiked,
    );
  }
  throw ArgumentError('Unsupported article type: ${article.runtimeType}');
}

class _Thumbnail extends StatelessWidget {
  final String url;
  final bool isVideo;
  final Color accent;

  const _Thumbnail({
    required this.url,
    required this.isVideo,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final placeholder = Container(
      width: 78,
      height: 78,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            accent.withValues(alpha: 0.12),
            accent.withValues(alpha: 0.04),
          ],
        ),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        isVideo ? Icons.play_arrow_rounded : Icons.article_outlined,
        color: colors.textTertiary,
        size: 24,
      ),
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: FacteurImage(
        imageUrl: url,
        width: 78,
        height: 78,
        placeholder: (_) => placeholder,
        errorWidget: (_) => placeholder,
      ),
    );
  }
}

class _Footer extends StatelessWidget {
  final FluxArticleVM vm;
  final FacteurColors colors;
  final bool showPressReview;
  final int pressReviewCount;
  final List<SourceMini> perspectiveSources;

  const _Footer({
    required this.vm,
    required this.colors,
    required this.showPressReview,
    required this.pressReviewCount,
    required this.perspectiveSources,
  });

  @override
  Widget build(BuildContext context) {
    final separator = Text(
      '·',
      style: GoogleFonts.dmSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        color: colors.textTertiary.withValues(alpha: 0.55),
      ),
    );

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        _SourceDot(
          name: vm.sourceName,
          logoUrl: vm.sourceLogoUrl,
          accent: colors.primary,
          ringColor: colors.surface,
          size: 14,
        ),
        const SizedBox(width: 6),
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 92),
          child: Text(
            vm.sourceName,
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
              height: 1.4,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (!vm.isFollowedSource) ...[
          const SizedBox(width: 3),
          Text(
            '+',
            style: GoogleFonts.dmSans(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.primary,
              height: 1.4,
            ),
          ),
        ],
        if (vm.themeLabel != null && vm.themeLabel!.trim().isNotEmpty) ...[
          const SizedBox(width: 6),
          _ThemePill(label: vm.themeLabel!, colors: colors),
        ],
        const SizedBox(width: 6),
        separator,
        const SizedBox(width: 6),
        Icon(PhosphorIconsRegular.clock,
            size: 12, color: colors.textTertiary),
        const SizedBox(width: 3),
        Text(
          _publishedAtShort(vm.publishedAt),
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: colors.textTertiary,
            height: 1.4,
          ),
        ),
        if (showPressReview) ...[
          const Spacer(),
          _PressReviewChip(
            count: pressReviewCount,
            sources: perspectiveSources,
            colors: colors,
          ),
        ],
      ],
    );
  }

  String _publishedAtShort(DateTime? date) {
    if (date == null) return 'récent';
    return timeago
        .format(date, locale: 'fr_short')
        .replaceAll('il y a ', '')
        .trim();
  }
}

/// Source identity dot — logo when [logoUrl] is provided, initial otherwise.
class _SourceDot extends StatelessWidget {
  final String name;
  final String? logoUrl;
  final Color accent;
  final Color ringColor;
  final double size;

  const _SourceDot({
    required this.name,
    required this.logoUrl,
    required this.accent,
    required this.ringColor,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl != null && logoUrl!.trim().isNotEmpty;
    final initial = _Initial(name: name, fontSize: size * 0.55);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: ringColor,
            spreadRadius: 1.5,
            blurRadius: 0,
          ),
        ],
      ),
      child: hasLogo
          ? ClipOval(
              child: FacteurImage(
                imageUrl: logoUrl!,
                width: size,
                height: size,
                placeholder: (_) => initial,
                errorWidget: (_) => initial,
              ),
            )
          : initial,
    );
  }
}

class _Initial extends StatelessWidget {
  final String name;
  final double fontSize;

  const _Initial({required this.name, required this.fontSize});

  @override
  Widget build(BuildContext context) {
    final trimmed = name.trim();
    final initial =
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Text(
      initial,
      style: GoogleFonts.dmSans(
        fontSize: fontSize,
        fontWeight: FontWeight.w700,
        color: Colors.white,
        height: 1.0,
      ),
    );
  }
}

class _ThemePill extends StatelessWidget {
  final String label;
  final FacteurColors colors;

  const _ThemePill({required this.label, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          height: 1.4,
          color: colors.textSecondary,
        ),
      ),
    );
  }
}

/// Trailing for Essentiel cards: stacks up to 3 source logos with a 4-px
/// overlap, followed by a "+N" count chip.
class _PressReviewChip extends StatelessWidget {
  final int count;
  final List<SourceMini> sources;
  final FacteurColors colors;

  const _PressReviewChip({
    required this.count,
    required this.sources,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    const dotSize = 12.0;
    const overlap = 4.0;
    final visibleCount = sources.length < 3 ? sources.length : 3;
    final stackWidth = visibleCount == 0
        ? 0.0
        : dotSize + (visibleCount - 1) * (dotSize - overlap);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visibleCount > 0)
          SizedBox(
            width: stackWidth,
            height: dotSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < visibleCount; i++)
                  Positioned(
                    left: i * (dotSize - overlap),
                    child: _SourceDot(
                      name: sources[i].name,
                      logoUrl: sources[i].logoUrl,
                      accent: colors.primary,
                      ringColor: colors.surface,
                      size: dotSize,
                    ),
                  ),
              ],
            ),
          ),
        if (visibleCount > 0) const SizedBox(width: 6),
        Text(
          '+$count',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}
