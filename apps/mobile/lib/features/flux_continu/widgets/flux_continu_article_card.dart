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
  final String? themeLabel;
  final ContentType contentType;
  final int? durationSeconds;

  const FluxArticleVM({
    required this.contentId,
    required this.title,
    required this.sourceName,
    required this.contentType,
    this.thumbnailUrl,
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

  const FluxContinuArticleCard({
    super.key,
    required this.article,
    this.onTap,
    this.isEssentiel = false,
    this.pressReviewCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final vm = FluxArticleVM.from(article);
    final colors = context.facteurColors;

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
                      const SizedBox(width: 12),
                      _Thumbnail(
                        url: vm.thumbnailUrl,
                        isVideo: _isVideo(vm.contentType),
                        accent: colors.primary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _Footer(
                    vm: vm,
                    colors: colors,
                    showPressReview: isEssentiel && pressReviewCount > 0,
                    pressReviewCount: pressReviewCount,
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
  final String? url;
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

    if (url == null || url!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 72,
        height: 72,
        child: Image.network(
          url!,
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

  const _Footer({
    required this.vm,
    required this.colors,
    required this.showPressReview,
    required this.pressReviewCount,
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
        _SourceDot(initial: _initial(vm.sourceName), accent: colors.primary,
            ringColor: colors.surface),
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
            colors: colors,
          ),
        ],
      ],
    );
  }

  String _initial(String name) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) return '?';
    return trimmed.characters.first.toUpperCase();
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

class _SourceDot extends StatelessWidget {
  final String initial;
  final Color accent;
  final Color ringColor;

  const _SourceDot({
    required this.initial,
    required this.accent,
    required this.ringColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
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
      child: Text(
        initial,
        style: GoogleFonts.dmSans(
          fontSize: 8,
          fontWeight: FontWeight.w700,
          color: Colors.white,
          height: 1.0,
        ),
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

class _PressReviewChip extends StatelessWidget {
  final int count;
  final FacteurColors colors;

  const _PressReviewChip({required this.count, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 12,
          child: Stack(
            children: List.generate(3, (i) {
              return Positioned(
                left: i * 4.0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceElevated,
                    border: Border.all(color: colors.surface, width: 1),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 4),
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
