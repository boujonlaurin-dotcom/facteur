import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../../widgets/design/facteur_image.dart';
import '../models/smart_search_result.dart';

class SourceResultCard extends StatelessWidget {
  final SmartSearchResult result;
  final VoidCallback onAdd;
  final VoidCallback onPreview;
  final bool isAdded;

  const SourceResultCard({
    super.key,
    required this.result,
    required this.onAdd,
    required this.onPreview,
    this.isAdded = false,
  });

  IconData _typeIcon() {
    switch (result.type) {
      case 'youtube':
        return PhosphorIcons.youtubeLogo(PhosphorIconsStyle.fill);
      case 'reddit':
        return PhosphorIcons.redditLogo(PhosphorIconsStyle.fill);
      case 'podcast':
        return PhosphorIcons.microphone(PhosphorIconsStyle.fill);
      default:
        return PhosphorIcons.rss(PhosphorIconsStyle.fill);
    }
  }

  String _typeLabel() {
    switch (result.type) {
      case 'youtube':
        return 'YouTube';
      case 'reddit':
        return 'Reddit';
      case 'podcast':
        return 'Podcast';
      case 'rss':
      case 'atom':
        return 'RSS';
      default:
        return 'Article';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final recentTitles = result.recentItems.take(3).toList();

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.border),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header: favicon + name + type
          Row(
            children: [
              _buildFavicon(colors),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      result.name,
                      style: Theme.of(context).textTheme.titleSmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Icon(_typeIcon(), size: 14, color: colors.textTertiary),
                        const SizedBox(width: 4),
                        Text(
                          _typeLabel(),
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: colors.textTertiary,
                                  ),
                        ),
                        if (result.inCatalog) ...[
                          const SizedBox(width: 8),
                          Icon(
                              PhosphorIcons.sealCheck(
                                  PhosphorIconsStyle.fill),
                              size: 14,
                              color: colors.primary),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),

          // Description
          if (result.description != null &&
              result.description!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              result.description!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.textSecondary,
                  ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],

          // Recent items
          if (recentTitles.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              'Derniers articles :',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
            ),
            const SizedBox(height: 6),
            ...recentTitles.map((item) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Icon(
                          PhosphorIcons.dotOutline(PhosphorIconsStyle.fill),
                          size: 14,
                          color: colors.primary),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          item.title,
                          style: Theme.of(context).textTheme.bodySmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                )),
          ],

          // CTAs
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onPreview,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    side: BorderSide(color: colors.border),
                  ),
                  child: Text(
                    'Apercu',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: isAdded
                    ? OutlinedButton.icon(
                        onPressed: null,
                        icon: Icon(
                            PhosphorIcons.checkCircle(
                                PhosphorIconsStyle.fill),
                            size: 18,
                            color: colors.success),
                        label: Text('Ajoutee',
                            style: TextStyle(color: colors.success)),
                        style: OutlinedButton.styleFrom(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          side: BorderSide(color: colors.success),
                        ),
                      )
                    : ElevatedButton(
                        onPressed: onAdd,
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          backgroundColor: colors.primary,
                          foregroundColor: colors.textPrimary,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: const Text('Ajouter'),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildFavicon(FacteurColors colors) {
    if (result.faviconUrl != null && result.faviconUrl!.isNotEmpty) {
      return Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: FacteurImage(
          imageUrl: result.faviconUrl!,
          fit: BoxFit.cover,
          errorWidget: (context) => Container(
            color: colors.backgroundSecondary,
            child: Icon(_typeIcon(), color: colors.primary, size: 22),
          ),
        ),
      );
    }
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(_typeIcon(), color: colors.primary, size: 22),
    );
  }
}
