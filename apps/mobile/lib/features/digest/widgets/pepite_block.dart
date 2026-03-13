import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../models/digest_models.dart';
import 'digest_card.dart';

/// Editorial wrapper for the pépite article.
/// Displays a mini-editorial text above a DigestCard with badge "pepite".
class PepiteBlock extends StatelessWidget {
  final PepiteResponse pepite;
  final void Function(DigestItem) onTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final bool isSerene;

  const PepiteBlock({
    super.key,
    required this.pepite,
    required this.onTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
    this.isSerene = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final item = _toDigestItem();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Mini-editorial text
        if (pepite.miniEditorial.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(
              left: 4,
              right: 4,
              bottom: 10,
            ),
            child: Text(
              pepite.miniEditorial,
              style: TextStyle(
                fontStyle: FontStyle.italic,
                fontSize: 14,
                height: 1.5,
                color: isDark
                    ? Colors.white.withValues(alpha: 0.8)
                    : colors.textSecondary,
              ),
            ),
          ),

        // Pépite card
        DigestCard(
          item: item,
          isSerene: isSerene,
          onTap: () => onTap(item),
          onAction: (action) => _handleAction(action, item),
        ),
      ],
    );
  }

  void _handleAction(String action, DigestItem item) {
    switch (action) {
      case 'like':
        onLike?.call(item);
      case 'save':
        onSave?.call(item);
      case 'not_interested':
        onNotInterested?.call(item);
      case 'read':
        onTap(item);
    }
  }

  DigestItem _toDigestItem() {
    return DigestItem(
      contentId: pepite.contentId,
      title: pepite.title,
      url: pepite.url,
      thumbnailUrl: pepite.thumbnailUrl,
      source: pepite.source,
      badge: pepite.badge,
      isRead: pepite.isRead,
      isSaved: pepite.isSaved,
      isLiked: pepite.isLiked,
      isDismissed: pepite.isDismissed,
    );
  }
}
