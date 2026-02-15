import 'package:cached_network_image/cached_network_image.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

/// Modal de preview d'article, déclenchée par un long-press.
/// Affiche une carte agrandie avec la description RSS.
class ArticlePreviewModal extends StatelessWidget {
  final Content content;
  final VoidCallback onOpen;

  const ArticlePreviewModal({
    super.key,
    required this.content,
    required this.onOpen,
  });

  /// Affiche la preview avec animation scale+fade.
  static void show(
    BuildContext context,
    Content content,
    VoidCallback onOpen,
  ) {
    showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'Fermer la preview',
      barrierColor: Colors.black.withValues(alpha: 0.6),
      transitionDuration: const Duration(milliseconds: 250),
      transitionBuilder: (context, animation, secondaryAnimation, child) {
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: Curves.easeOutCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(curvedAnimation),
          child: FadeTransition(
            opacity: curvedAnimation,
            child: child,
          ),
        );
      },
      pageBuilder: (context, animation, secondaryAnimation) {
        return ArticlePreviewModal(
          content: content,
          onOpen: onOpen,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final screenSize = MediaQuery.of(context).size;

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: screenSize.width * 0.9,
          maxHeight: screenSize.height * 0.75,
        ),
        child: Material(
          color: Colors.transparent,
          child: Container(
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.25),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(FacteurRadius.large),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Thumbnail
                    if (content.thumbnailUrl != null &&
                        content.thumbnailUrl!.isNotEmpty)
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: CachedNetworkImage(
                          imageUrl: content.thumbnailUrl!,
                          fit: BoxFit.cover,
                          placeholder: (context, url) => Container(
                            color: colors.backgroundSecondary,
                            child: Center(
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: colors.primary.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          errorWidget: (context, url, error) => Container(
                            color: colors.backgroundSecondary,
                            child: Icon(
                              PhosphorIcons.imageBroken(
                                  PhosphorIconsStyle.duotone),
                              color: colors.textSecondary,
                              size: 32,
                            ),
                          ),
                        ),
                      ),

                    Padding(
                      padding: const EdgeInsets.all(FacteurSpacing.space4),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Source row
                          Row(
                            children: [
                              if (content.source.logoUrl != null &&
                                  content.source.logoUrl!.isNotEmpty) ...[
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: CachedNetworkImage(
                                    imageUrl: content.source.logoUrl!,
                                    width: 20,
                                    height: 20,
                                    fit: BoxFit.cover,
                                    errorWidget: (context, url, error) =>
                                        _buildSourcePlaceholder(colors),
                                  ),
                                ),
                                const SizedBox(width: FacteurSpacing.space2),
                              ] else ...[
                                _buildSourcePlaceholder(colors),
                                const SizedBox(width: FacteurSpacing.space2),
                              ],
                              Flexible(
                                child: Text(
                                  content.source.name,
                                  style: textTheme.labelMedium?.copyWith(
                                    color: colors.textPrimary,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: FacteurSpacing.space2),
                              Text(
                                timeago
                                    .format(content.publishedAt,
                                        locale: 'fr_short')
                                    .replaceAll('il y a ', ''),
                                style: textTheme.labelSmall?.copyWith(
                                  color: colors.textSecondary,
                                  fontSize: 11,
                                ),
                              ),
                            ],
                          ),

                          const SizedBox(height: FacteurSpacing.space3),

                          // Title
                          Text(
                            content.title,
                            style: textTheme.displaySmall?.copyWith(
                              fontSize: 20,
                              fontWeight: FontWeight.w700,
                              height: 1.2,
                            ),
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                          ),

                          // Description RSS
                          if (content.description != null &&
                              content.description!.isNotEmpty) ...[
                            const SizedBox(height: FacteurSpacing.space3),
                            Text(
                              content.description!,
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                                height: 1.4,
                              ),
                              maxLines: 8,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],

                          const SizedBox(height: FacteurSpacing.space3),

                          // Metadata row (type + duration)
                          Row(
                            children: [
                              _buildTypeIcon(context, content.contentType),
                              if (content.durationSeconds != null) ...[
                                const SizedBox(width: FacteurSpacing.space2),
                                Text(
                                  _formatDuration(content.durationSeconds!),
                                  style: textTheme.labelSmall?.copyWith(
                                    color: colors.textSecondary,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ],
                            ],
                          ),

                          const SizedBox(height: FacteurSpacing.space4),

                          // CTA button
                          SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              onPressed: () {
                                Navigator.of(context).pop();
                                onOpen();
                              },
                              icon: Icon(
                                _ctaIcon(content.contentType),
                                size: 18,
                              ),
                              label: Text(_ctaLabel(content.contentType)),
                              style: FilledButton.styleFrom(
                                backgroundColor: colors.primary,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  vertical: FacteurSpacing.space3,
                                ),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(
                                      FacteurRadius.small),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSourcePlaceholder(FacteurColors colors) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Center(
        child: Text(
          content.source.name.isNotEmpty
              ? content.source.name.substring(0, 1).toUpperCase()
              : '?',
          style: TextStyle(
            fontSize: 10,
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
        icon = PhosphorIcons.filmStrip(PhosphorIconsStyle.fill);
        break;
      case ContentType.audio:
        icon = PhosphorIcons.headphones(PhosphorIconsStyle.fill);
        break;
      default:
        return const SizedBox.shrink();
    }

    return Icon(icon, size: 14, color: colors.textSecondary);
  }

  static String _formatDuration(int seconds) {
    if (seconds < 60) return '${seconds}s';
    final minutes = (seconds / 60).ceil();
    return '$minutes min';
  }

  static String _ctaLabel(ContentType type) {
    switch (type) {
      case ContentType.video:
      case ContentType.youtube:
        return 'Regarder';
      case ContentType.audio:
        return 'Écouter';
      default:
        return "Lire l'article";
    }
  }

  static IconData _ctaIcon(ContentType type) {
    switch (type) {
      case ContentType.video:
      case ContentType.youtube:
        return PhosphorIcons.play(PhosphorIconsStyle.fill);
      case ContentType.audio:
        return PhosphorIcons.headphones(PhosphorIconsStyle.fill);
      default:
        return PhosphorIcons.arrowSquareOut();
    }
  }
}
