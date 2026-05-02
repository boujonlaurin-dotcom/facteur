import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../models/veille_delivery.dart';

/// Carte représentant un cluster d'articles dans la livraison de veille.
class VeilleClusterCard extends StatelessWidget {
  final VeilleDeliveryItem item;
  final void Function(VeilleDeliveryArticle) onArticleTap;

  const VeilleClusterCard({
    super.key,
    required this.item,
    required this.onArticleTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE6E1D6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            item.title,
            style: GoogleFonts.dmSans(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: const Color(0xFF2A2419),
            ),
          ),
          if (item.whyItMatters.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF5EFE0),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    PhosphorIcons.lightbulb(),
                    size: 14,
                    color: const Color(0xFF8B7E63),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      item.whyItMatters,
                      style: GoogleFonts.dmSans(
                        fontSize: 13,
                        height: 1.4,
                        color: const Color(0xFF5C5240),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 14),
          for (var i = 0; i < item.articles.length; i++) ...[
            if (i > 0) const Divider(height: 18, color: Color(0xFFEFE9DA)),
            _ArticleRow(
              article: item.articles[i],
              onTap: () => onArticleTap(item.articles[i]),
            ),
          ],
        ],
      ),
    );
  }
}

class _ArticleRow extends StatelessWidget {
  final VeilleDeliveryArticle article;
  final VoidCallback onTap;

  const _ArticleRow({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.title,
              style: GoogleFonts.dmSans(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: const Color(0xFF2A2419),
              ),
            ),
            if (article.excerpt.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                article.excerpt,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.dmSans(
                  fontSize: 12,
                  height: 1.4,
                  color: const Color(0xFF8B7E63),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
