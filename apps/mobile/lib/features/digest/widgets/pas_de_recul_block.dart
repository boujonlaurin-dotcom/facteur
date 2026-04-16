import 'package:flutter/material.dart';
import '../../../config/theme.dart';
import '../../../widgets/design/facteur_thumbnail.dart';
import '../models/digest_models.dart';
import 'editorial_badge.dart';

/// Companion block for the deep analysis article ("Pas de recul").
/// Displayed in the expanded toggle state of a topic.
///
/// When [introText] is provided, it is rendered as a collapsible section
/// (toggle "Pourquoi cet article ?" / "Réduire") and tapping the card outside
/// the article row toggles the text visibility — only tapping the title +
/// thumbnail block opens the article. When [introText] is null the whole
/// card opens the article on tap (legacy behavior).
class PasDeReculBlock extends StatefulWidget {
  final DigestItem deepArticle;
  final String? introText;
  final VoidCallback? onTap;

  const PasDeReculBlock({
    super.key,
    required this.deepArticle,
    this.introText,
    this.onTap,
  });

  @override
  State<PasDeReculBlock> createState() => _PasDeReculBlockState();
}

class _PasDeReculBlockState extends State<PasDeReculBlock> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final badgeChip = EditorialBadge.chip('pas_de_recul', context: context);
    final hasIntro = widget.introText != null;

    final decoration = BoxDecoration(
      color: colors.info.withOpacity(isDark ? 0.10 : 0.05),
      border: Border.all(
        color: colors.info.withOpacity(0.08),
        width: 1,
      ),
      borderRadius: BorderRadius.circular(12),
    );

    // Inner article block (title + source + thumbnail). Wrapped in its own
    // InkWell so taps on this region open the article even when the parent
    // InkWell toggles the intro text.
    final articleRow = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: widget.onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title + source
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.deepArticle.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: isDark ? Colors.white : colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (widget.deepArticle.source?.name != null)
                          Text(
                            widget.deepArticle.source!.name,
                            style: TextStyle(
                              fontSize: 12,
                              color: isDark
                                  ? Colors.white.withOpacity(0.5)
                                  : colors.textSecondary.withOpacity(0.7),
                            ),
                          ),
                        const SizedBox(width: 4),
                        Icon(
                          Icons.arrow_forward_ios,
                          size: 12,
                          color: colors.info,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 60,
                height: 60,
                child: FacteurThumbnail(
                  imageUrl: widget.deepArticle.thumbnailUrl,
                  aspectRatio: 1.0,
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Legacy path: no intro text → whole card opens the article.
    if (!hasIntro) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.all(10),
            decoration: decoration,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badgeChip != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: badgeChip,
                  ),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.deepArticle.title,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w700,
                                color:
                                    isDark ? Colors.white : colors.textSecondary,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                if (widget.deepArticle.source?.name != null)
                                  Text(
                                    widget.deepArticle.source!.name,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: isDark
                                          ? Colors.white.withOpacity(0.5)
                                          : colors.textSecondary
                                              .withOpacity(0.7),
                                    ),
                                  ),
                                const SizedBox(width: 4),
                                Icon(
                                  Icons.arrow_forward_ios,
                                  size: 12,
                                  color: colors.info,
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      SizedBox(
                        width: 60,
                        height: 60,
                        child: FacteurThumbnail(
                          imageUrl: widget.deepArticle.thumbnailUrl,
                          aspectRatio: 1.0,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // With intro text: parent InkWell toggles the collapsible intro. Inner
    // InkWell on articleRow intercepts taps to open the article.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => setState(() => _isExpanded = !_isExpanded),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: decoration,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (badgeChip != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: badgeChip,
                ),

              articleRow,

              // Toggle: collapsed shows "Pourquoi cet article ?", expanded shows
              // "Réduire" chevron + intro text.
              const SizedBox(height: 10),
              if (!_isExpanded)
                Row(
                  children: [
                    Icon(
                      Icons.expand_more,
                      size: 16,
                      color: colors.primary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Pourquoi cet article ?',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                )
              else ...[
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Icon(
                      Icons.expand_less,
                      size: 16,
                      color: colors.primary.withOpacity(0.7),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Réduire',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.primary.withOpacity(0.7),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  widget.introText!,
                  style: TextStyle(
                    fontSize: 14,
                    height: 1.5,
                    color: isDark
                        ? Colors.white.withOpacity(0.85)
                        : colors.textSecondary,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
