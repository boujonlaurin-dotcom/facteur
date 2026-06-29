import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';
import '../providers/edition_essentiel_provider.dart';
import '../utils/morning_ritual_format.dart';

/// EPIC « Lettre du jour » — rétro « Cette semaine » en **liste plate par jour**
/// (maquette `CarteOverlay`). Remplace la carte héros agrégée par un récap : un
/// en-tête de date (jour long FR + filet + compteur) suivi des Essentiels de ce
/// jour, du plus récent au plus ancien.
///
/// Lecture seule : un tap ouvre le reader via [onTapArticle], aucune mutation.
/// Widget **public** pour pouvoir le tester isolément.
class WeekRecapBlock extends StatelessWidget {
  final List<EditionDayGroup> weekDays;
  final void Function(EssentielArticle) onTapArticle;

  const WeekRecapBlock({
    super.key,
    required this.weekDays,
    required this.onTapArticle,
  });

  @override
  Widget build(BuildContext context) {
    if (weekDays.isEmpty) return const SizedBox.shrink();
    return Padding(
      // Gutter aligné sur le contenu des sections (cartes = 12px horizontal).
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final (i, group) in weekDays.indexed) ...[
            if (i > 0) const SizedBox(height: 20),
            _DayHeader(date: group.date, count: group.articles.length),
            const SizedBox(height: 14),
            for (final (j, article) in group.articles.indexed) ...[
              if (j > 0) const SizedBox(height: 14),
              _ArticleRow(
                article: article,
                onTap: () => onTapArticle(article),
              ),
            ],
          ],
        ],
      ),
    );
  }
}

/// En-tête de groupe-jour : « mercredi 27 mai » + filet + « N article(s) ».
class _DayHeader extends StatelessWidget {
  final DateTime date;
  final int count;

  const _DayHeader({required this.date, required this.count});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Text(
          formatFrenchLongDate(date),
          style: GoogleFonts.dmSans(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(child: Divider(height: 1, thickness: 1, color: colors.border)),
        const SizedBox(width: 10),
        Text(
          '$count article${count > 1 ? 's' : ''}',
          style: GoogleFonts.dmSans(
            fontSize: 11,
            fontWeight: FontWeight.w500,
            color: colors.textTertiary,
          ),
        ),
      ],
    );
  }
}

/// Une ligne d'article du récap : source (tertiaire) + titre (Fraunces). Tap →
/// reader. Estompé quand l'article est déjà lu (anti-FOMO discret).
class _ArticleRow extends StatelessWidget {
  final EssentielArticle article;
  final VoidCallback onTap;

  const _ArticleRow({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(FacteurRadius.small),
      child: Opacity(
        opacity: article.isRead ? 0.55 : 1,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              article.sourceName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.dmSans(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: colors.textTertiary,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              article.title,
              style: GoogleFonts.fraunces(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                height: 1.25,
                color: colors.textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
