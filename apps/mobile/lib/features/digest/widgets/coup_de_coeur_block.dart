import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../models/digest_models.dart';
import 'digest_card.dart';

/// Editorial wrapper for the coup de cœur article.
/// Displays a DigestCard with badge "coup_de_coeur" and a save count label.
class CoupDeCoeurBlock extends StatelessWidget {
  final CoupDeCoeurResponse coupDeCoeur;
  final void Function(DigestItem) onTap;
  final void Function(DigestItem)? onLike;
  final void Function(DigestItem)? onSave;
  final void Function(DigestItem)? onNotInterested;
  final bool isSerene;

  const CoupDeCoeurBlock({
    super.key,
    required this.coupDeCoeur,
    required this.onTap,
    this.onLike,
    this.onSave,
    this.onNotInterested,
    this.isSerene = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final item = _toDigestItem();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Coup de cœur card
        DigestCard(
          item: item,
          isSerene: isSerene,
          onTap: () => onTap(item),
          onAction: (action) => _handleAction(action, item),
        ),

        // Save count label
        if (coupDeCoeur.saveCount > 0)
          Padding(
            padding: const EdgeInsets.only(left: 4, top: 6),
            child: Text(
              'Gardé par ${coupDeCoeur.saveCount} lecteurs',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: colors.textSecondary,
              ),
            ),
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
      contentId: coupDeCoeur.contentId,
      title: coupDeCoeur.title,
      url: coupDeCoeur.url,
      thumbnailUrl: coupDeCoeur.thumbnailUrl,
      source: coupDeCoeur.source,
      badge: coupDeCoeur.badge,
      isRead: coupDeCoeur.isRead,
      isSaved: coupDeCoeur.isSaved,
      isLiked: coupDeCoeur.isLiked,
      isDismissed: coupDeCoeur.isDismissed,
    );
  }
}
