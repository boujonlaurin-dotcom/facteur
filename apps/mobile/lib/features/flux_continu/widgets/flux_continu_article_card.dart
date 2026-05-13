import 'package:flutter/material.dart';

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
  final String? description;
  final String? thumbnailUrl;
  final String sourceName;
  final String? sourceLogoUrl;
  final ContentType contentType;
  final int? durationSeconds;

  const FluxArticleVM({
    required this.contentId,
    required this.title,
    required this.sourceName,
    required this.contentType,
    this.description,
    this.thumbnailUrl,
    this.sourceLogoUrl,
    this.durationSeconds,
  });

  factory FluxArticleVM.from(Object article) {
    if (article is DigestItem) {
      return FluxArticleVM(
        contentId: article.contentId,
        title: article.title,
        description: article.description,
        thumbnailUrl: article.thumbnailUrl,
        sourceName: article.source?.name ?? 'Inconnu',
        sourceLogoUrl: article.source?.logoUrl,
        contentType: article.contentType,
        durationSeconds: article.durationSeconds,
      );
    }
    if (article is Content) {
      return FluxArticleVM(
        contentId: article.id,
        title: article.title,
        description: article.description,
        thumbnailUrl: article.thumbnailUrl,
        sourceName: article.source.name,
        sourceLogoUrl: article.source.logoUrl,
        contentType: article.contentType,
        durationSeconds: article.durationSeconds,
      );
    }
    throw ArgumentError('Unsupported article type: ${article.runtimeType}');
  }
}

/// Article list item for the Flux Continu V1.8.
///
/// Horizontal layout: 72×72 thumbnail on the left, title + description on
/// the right, single-line footer with source · reading time · optional
/// press-review chip (Essentiel section only).
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
    final textTheme = Theme.of(context).textTheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FacteurRadius.small),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: FacteurSpacing.space4,
          vertical: FacteurSpacing.space3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Thumbnail(url: vm.thumbnailUrl, isVideo: _isVideo(vm.contentType)),
            const SizedBox(width: FacteurSpacing.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    vm.title,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (vm.description != null &&
                      vm.description!.trim().isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      vm.description!,
                      style: textTheme.bodySmall?.copyWith(
                        color: colors.textSecondary,
                        height: 1.4,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: FacteurSpacing.space2),
                  _Footer(
                    vm: vm,
                    colors: colors,
                    showPressReview: isEssentiel && pressReviewCount > 0,
                    pressReviewCount: pressReviewCount,
                  ),
                ],
              ),
            ),
          ],
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

  const _Thumbnail({required this.url, required this.isVideo});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final placeholder = Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: BorderRadius.circular(FacteurRadius.small),
      ),
      child: Icon(
        isVideo ? Icons.play_arrow_rounded : Icons.article_outlined,
        color: colors.textTertiary,
        size: 28,
      ),
    );

    if (url == null || url!.isEmpty) return placeholder;

    return ClipRRect(
      borderRadius: BorderRadius.circular(FacteurRadius.small),
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
    final textTheme = Theme.of(context).textTheme;
    final footerStyle = textTheme.labelSmall?.copyWith(
      color: colors.textTertiary,
      letterSpacing: 0,
    );

    return Row(
      mainAxisSize: MainAxisSize.max,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.textTertiary,
          ),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            vm.sourceName,
            style: footerStyle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 8),
        _NeutralTag(label: _readingTimeLabel(vm)),
        if (showPressReview) ...[
          const SizedBox(width: 8),
          _PressReviewChip(count: pressReviewCount),
        ],
      ],
    );
  }

  String _readingTimeLabel(FluxArticleVM vm) {
    if (vm.contentType == ContentType.video ||
        vm.contentType == ContentType.youtube ||
        vm.contentType == ContentType.audio) {
      final s = vm.durationSeconds;
      if (s != null && s > 0) {
        final m = (s / 60).ceil();
        return '$m min';
      }
    }
    // Articles : pas de field reading_time côté backend pour les digests,
    // on affiche une estimation courte par défaut. La vraie estimation
    // viendra avec un champ dédié quand le backend l'exposera.
    return '5 min';
  }
}

class _NeutralTag extends StatelessWidget {
  final String label;
  const _NeutralTag({required this.label});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: colors.textPrimary.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(FacteurRadius.small),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: colors.textSecondary,
              letterSpacing: 0,
            ),
      ),
    );
  }
}

class _PressReviewChip extends StatelessWidget {
  final int count;
  const _PressReviewChip({required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 22,
          height: 12,
          child: Stack(
            children: List.generate(3, (i) {
              return Positioned(
                left: i * 5.0,
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: colors.surfaceElevated,
                    border: Border.all(color: colors.border, width: 1),
                  ),
                ),
              );
            }),
          ),
        ),
        const SizedBox(width: 4),
        Text(
          '+$count',
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: colors.textSecondary,
              ),
        ),
      ],
    );
  }
}
