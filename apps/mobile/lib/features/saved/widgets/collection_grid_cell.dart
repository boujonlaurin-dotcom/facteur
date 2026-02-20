import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/collection_model.dart';

/// Cellule de la grille de collections (mosaïque 2x2 + nom + compteur).
class CollectionGridCell extends StatelessWidget {
  final Collection collection;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const CollectionGridCell({
    super.key,
    required this.collection,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Thumbnail mosaic
          AspectRatio(
            aspectRatio: 1,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: collection.thumbnails.isEmpty
                  ? _EmptyPlaceholder(colors: colors)
                  : _ThumbnailMosaic(
                      thumbnails: collection.thumbnails,
                      colors: colors,
                    ),
            ),
          ),
          const SizedBox(height: 8),
          // Name
          Text(
            collection.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          // Count + progress
          Text(
            _buildSubtitle(),
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  String _buildSubtitle() {
    final count = collection.itemCount;
    final read = collection.readCount;
    if (count == 0) return 'Vide';
    final suffix = count == 1 ? 'article' : 'articles';
    if (read > 0) return '$read/$count lus';
    return '$count $suffix';
  }
}

/// "Tous les articles" special cell.
class AllArticlesGridCell extends StatelessWidget {
  final int totalCount;
  final int readCount;
  final List<String?> thumbnails;
  final VoidCallback onTap;

  const AllArticlesGridCell({
    super.key,
    required this.totalCount,
    required this.readCount,
    required this.thumbnails,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.primary.withValues(alpha: 0.3),
                  width: 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: thumbnails.isEmpty
                    ? _EmptyPlaceholder(
                        colors: colors,
                        icon: PhosphorIcons.bookmarksSimple(
                            PhosphorIconsStyle.duotone),
                      )
                    : _ThumbnailMosaic(
                        thumbnails: thumbnails,
                        colors: colors,
                      ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tous les articles',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: colors.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            totalCount == 0
                ? 'Vide'
                : readCount > 0
                    ? '$readCount/$totalCount lus'
                    : '$totalCount ${totalCount == 1 ? 'article' : 'articles'}',
            style: TextStyle(
              color: colors.textTertiary,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bouton "+ Nouvelle collection".
class NewCollectionCell extends StatelessWidget {
  final VoidCallback onTap;

  const NewCollectionCell({super.key, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return GestureDetector(
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: colors.textTertiary.withValues(alpha: 0.3),
                  width: 1,
                  // Dashed effect approximated with dotted border pattern
                ),
                color: colors.surface,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.plus(PhosphorIconsStyle.regular),
                      size: 32,
                      color: colors.textTertiary,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Nouvelle\ncollection',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: colors.textTertiary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Empty space to align with other cells
          const SizedBox(height: 18),
        ],
      ),
    );
  }
}

class _EmptyPlaceholder extends StatelessWidget {
  final FacteurColors colors;
  final IconData? icon;

  const _EmptyPlaceholder({required this.colors, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: colors.backgroundSecondary,
      child: Center(
        child: Icon(
          icon ??
              PhosphorIcons.bookmarkSimple(PhosphorIconsStyle.duotone),
          size: 40,
          color: colors.textTertiary,
        ),
      ),
    );
  }
}

class _ThumbnailMosaic extends StatelessWidget {
  final List<String?> thumbnails;
  final FacteurColors colors;

  const _ThumbnailMosaic({required this.thumbnails, required this.colors});

  @override
  Widget build(BuildContext context) {
    // Build a 2x2 grid of thumbnails
    return Column(
      children: [
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildTile(0)),
              const SizedBox(width: 2),
              Expanded(child: _buildTile(1)),
            ],
          ),
        ),
        const SizedBox(height: 2),
        Expanded(
          child: Row(
            children: [
              Expanded(child: _buildTile(2)),
              const SizedBox(width: 2),
              Expanded(child: _buildTile(3)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildTile(int index) {
    final url = index < thumbnails.length ? thumbnails[index] : null;
    if (url == null || url.isEmpty) {
      return Container(color: colors.backgroundSecondary);
    }
    return CachedNetworkImage(
      imageUrl: url,
      fit: BoxFit.cover,
      placeholder: (_, __) => Container(color: colors.backgroundSecondary),
      errorWidget: (_, __, ___) =>
          Container(color: colors.backgroundSecondary),
    );
  }
}
