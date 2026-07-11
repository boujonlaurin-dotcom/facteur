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
                  _buildBadgeRow(context, badgeChip, colors),
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
                _buildBadgeRow(context, badgeChip, colors),

              articleRow,

              // Toggle: collapsed shows "Pourquoi cet article ?", expanded shows
              // "Réduire" chevron + intro text.
              const SizedBox(height: 10),
              if (!_isExpanded)
                Align(
                  alignment: Alignment.centerLeft,
                  child: SizedBox(
                    height: 30,
                    child: OutlinedButton(
                      onPressed: () => setState(() => _isExpanded = true),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colors.textSecondary,
                        side: BorderSide(
                          color: colors.textSecondary.withOpacity(0.25),
                          width: 0.8,
                        ),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 0),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.expand_more,
                            size: 14,
                            color: colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'Pourquoi cet article ?',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w500,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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

  /// Badge éditorial « Prendre du recul » + petit bouton info (i) à droite qui
  /// ouvre une explication de la rubrique. Le [GestureDetector] de l'icône
  /// gagne l'arène de gestes : sur la carte intro, taper le (i) n'enclenche pas
  /// le toggle parent.
  Widget _buildBadgeRow(BuildContext context, Widget chip, FacteurColors colors) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          chip,
          const SizedBox(width: 6),
          Semantics(
            button: true,
            label: 'À propos de « Pas de recul »',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => _showPasDeReculInfo(context, colors),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  Icons.info_outline,
                  size: 15,
                  color: colors.info.withOpacity(0.7),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Feuille du bas expliquant la rubrique « Pas de recul » : ce qu'elle est et
  /// comment Facteur sélectionne ces articles.
  void _showPasDeReculInfo(BuildContext context, FacteurColors colors) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Container(
        decoration: BoxDecoration(
          color: colors.backgroundPrimary,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: EdgeInsets.fromLTRB(
          20,
          12,
          20,
          24 + MediaQuery.of(sheetContext).padding.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: colors.textSecondary.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                const Text('\u{1F52D}', style: TextStyle(fontSize: 18)),
                const SizedBox(width: 8),
                Text(
                  'Pas de recul',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Quand un sujet domine l'actualité, Facteur met en avant un "
              'article qui prend de la hauteur : analyse de fond, mise en '
              "perspective ou angle inattendu, plutôt qu'une énième dépêche.",
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'Ces articles sont repérés automatiquement parmi des sources de '
              'qualité, en privilégiant les formats longs et explicatifs '
              '(décryptages, enquêtes, analyses argumentées) qui aident à '
              "comprendre plutôt qu'à suivre le flux.",
              style: TextStyle(
                fontSize: 14,
                height: 1.5,
                color: colors.textSecondary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
