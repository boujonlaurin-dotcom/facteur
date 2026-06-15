import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/smart_search_result.dart';

/// Liste des derniers articles d'une source (preview).
///
/// Extraite de [SourceDetailModal] pour être partagée avec la carte de
/// résultat smart-search en mode preuve (« Connecté »).
class RecentArticlesList extends StatelessWidget {
  final List<SmartSearchRecentItem> items;
  final int maxItems;
  final bool showHeader;

  const RecentArticlesList({
    super.key,
    required this.items,
    this.maxItems = 3,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final visible = items.take(maxItems).toList();
    if (visible.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.backgroundSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.textTertiary.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (showHeader) ...[
            Row(
              children: [
                Icon(
                    PhosphorIcons.newspaperClipping(
                        PhosphorIconsStyle.regular),
                    size: 18,
                    color: colors.primary),
                const SizedBox(width: 8),
                Text(
                  'Derniers articles',
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 10),
          ],
          ...visible.map((item) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: Icon(
                          PhosphorIcons.dotOutline(PhosphorIconsStyle.fill),
                          size: 12,
                          color: colors.primary),
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        item.title,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                              height: 1.4,
                            ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              )),
        ],
      ),
    );
  }
}
