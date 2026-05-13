import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';

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

  const FluxArticleVM({
    required this.contentId,
    required this.title,
    required this.sourceName,
    required this.contentType,
    this.thumbnailUrl,
    this.sourceLogoUrl,
    this.themeLabel,
    this.durationSeconds,
  });

  factory FluxArticleVM.from(Object article) {
    if (article is DigestItem) {
      return FluxArticleVM(
        contentId: article.contentId,
        title: article.title,
        thumbnailUrl: article.thumbnailUrl,
        sourceName: article.source?.name ?? 'Inconnu',
        sourceLogoUrl: article.source?.logoUrl,
        themeLabel: article.source?.theme,
        contentType: article.contentType,
        durationSeconds: article.durationSeconds,
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
  final bool isEssentiel;
  final int pressReviewCount;
  final List<SourceMini> perspectiveSources;

  const FluxContinuArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.isEssentiel = false,
    this.pressReviewCount = 0,
    this.perspectiveSources = const [],
  });

  @override
  Widget build(BuildContext context) {
    final vm = FluxArticleVM.from(article);
    final colors = context.facteurColors;
    final hasThumb = vm.thumbnailUrl != null && vm.thumbnailUrl!.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        elevation: 0,
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
              padding: const EdgeInsets.all(12),
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
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            height: 1.3,
                            letterSpacing: -0.15,
                            color: colors.textPrimary,
                          ),
                          maxLines: 4,
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
                  const SizedBox(height: 8),
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
    );
  }

  bool _isVideo(ContentType type) =>
      type == ContentType.video || type == ContentType.youtube;
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
      width: 72,
      height: 72,
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
      child: SizedBox(
        width: 72,
        height: 72,
        child: Image.network(
          url,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => placeholder,
          loadingBuilder: (_, child, progress) =>
              progress == null ? child : placeholder,
        ),
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
          _readingTimeLabel(vm),
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

  String _readingTimeLabel(FluxArticleVM vm) {
    if (vm.contentType == ContentType.video ||
        vm.contentType == ContentType.youtube ||
        vm.contentType == ContentType.audio) {
      final s = vm.durationSeconds;
      if (s != null && s > 0) return '${(s / 60).ceil()} min';
    }
    return '5 min';
  }
}

/// Renders a source identity dot: the source's logo when available,
/// otherwise the source's first letter on a colored circle.
///
/// The parchment-tinted ring around the dot is reproduced via a 0-blur
/// BoxShadow with [ringColor] (the card surface).
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
    this.size = 14,
  });

  @override
  Widget build(BuildContext context) {
    final hasLogo = logoUrl != null && logoUrl!.trim().isNotEmpty;
    final dot = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: hasLogo ? Colors.white : accent,
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
              child: Image.network(
                logoUrl!,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _Initial(
                  name: name,
                  fontSize: size * 0.55,
                ),
              ),
            )
          : _Initial(name: name, fontSize: size * 0.55),
    );
    return dot;
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

/// Press-review trailing for Essentiel cards: stacks up to 3 source logos
/// (from [topic.perspectiveSources]) with a 4-px overlap, followed by the
/// remaining-count chip "+N". Falls back to colored initial-circles when
/// no logo URL is available for a source.
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
    final visible = sources.take(3).toList();
    final stackWidth = visible.isEmpty
        ? 0.0
        : dotSize + (visible.length - 1) * (dotSize - overlap);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (visible.isNotEmpty)
          SizedBox(
            width: stackWidth,
            height: dotSize,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                for (var i = 0; i < visible.length; i++)
                  Positioned(
                    left: i * (dotSize - overlap),
                    child: _SourceDot(
                      name: visible[i].name,
                      logoUrl: visible[i].logoUrl,
                      accent: colors.primary,
                      ringColor: colors.surface,
                      size: dotSize,
                    ),
                  ),
              ],
            ),
          ),
        if (visible.isNotEmpty) const SizedBox(width: 6),
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
