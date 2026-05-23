import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';
import '../utils/theme_color_mapping.dart';

/// Carte hi-fi unique "L'Essentiel du jour" (Story 9.2, composant 1).
///
/// Présente jusqu'à 5 articles transversaux du jour :
///   - `articles[0]` → lead (fond teinté, bord gauche accent)
///   - `articles[1..2]` → médiums (filets fins)
///   - `articles[3..4]` → lights (filet pointillé, une ligne tronquée)
///
/// Le bouton config en haut-droite ouvre la modal `EssentielPersonalizeSheet`
/// pour rediriger vers `Mes intérêts` / `Mes sources` ; son tap est isolé
/// (`InkWell`) pour ne pas déclencher l'ouverture d'un article par erreur.
class EssentielHiFiCard extends StatelessWidget {
  final List<EssentielArticle> articles;
  final void Function(EssentielArticle article) onTapArticle;
  final VoidCallback onTapPersonalize;
  final VoidCallback? onTapSkip;
  final VoidCallback? onTapExploreAll;

  const EssentielHiFiCard({
    super.key,
    required this.articles,
    required this.onTapArticle,
    required this.onTapPersonalize,
    this.onTapSkip,
    this.onTapExploreAll,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final accent = colors.sectionEssentiel;

    final lead = articles.isNotEmpty ? articles.first : null;
    final mediums = articles.length > 1
        ? articles.sublist(1, articles.length > 3 ? 3 : articles.length)
        : const <EssentielArticle>[];
    final lights = articles.length > 3
        ? articles.sublist(3, articles.length > 5 ? 5 : articles.length)
        : const <EssentielArticle>[];

    return Container(
      margin: const EdgeInsets.fromLTRB(
        FacteurSpacing.space3,
        FacteurSpacing.space2,
        FacteurSpacing.space3,
        FacteurSpacing.space4,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(FacteurRadius.large),
        border: Border.all(color: colors.border, width: 0.6),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14000000),
            blurRadius: 14,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space4,
          FacteurSpacing.space4,
          FacteurSpacing.space4,
          FacteurSpacing.space3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(accent: accent, onTapPersonalize: onTapPersonalize),
            const SizedBox(height: FacteurSpacing.space4),
            if (lead != null)
              _LeadTile(
                article: lead,
                accent: accent,
                onTap: () => onTapArticle(lead),
              ),
            for (final m in mediums) ...[
              const SizedBox(height: FacteurSpacing.space3),
              const _Hairline(),
              const SizedBox(height: FacteurSpacing.space3),
              _MediumTile(article: m, onTap: () => onTapArticle(m)),
            ],
            for (final l in lights) ...[
              const SizedBox(height: FacteurSpacing.space2),
              const _DottedDivider(),
              const SizedBox(height: FacteurSpacing.space2),
              _LightTile(article: l, onTap: () => onTapArticle(l)),
            ],
            const SizedBox(height: FacteurSpacing.space4),
            _Footer(
              accent: accent,
              onSkip: onTapSkip,
              onExploreAll: onTapExploreAll,
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  final Color accent;
  final VoidCallback onTapPersonalize;

  const _Header({required this.accent, required this.onTapPersonalize});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final now = DateTime.now();
    final dateLabel = _formatDateStamp(now);
    final dayLabel = _formatDayName(now).toUpperCase();

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _DateStamp(label: dateLabel, accent: accent),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ÉDITION DU $dayLabel · 5 ACTUS À SUIVRE',
                style: FacteurTypography.stamp(colors.textTertiary),
              ),
              const SizedBox(height: 4),
              Text(
                'L’Essentiel du jour',
                style: GoogleFonts.fraunces(
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                  color: colors.textPrimary,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: FacteurSpacing.space2),
        _PersonalizeButton(onTap: onTapPersonalize),
      ],
    );
  }

  static String _formatDateStamp(DateTime d) {
    const months = [
      'JAN',
      'FÉV',
      'MAR',
      'AVR',
      'MAI',
      'JUIN',
      'JUIL',
      'AOÛT',
      'SEPT',
      'OCT',
      'NOV',
      'DÉC',
    ];
    final dd = d.day.toString().padLeft(2, '0');
    return '$dd / ${months[d.month - 1]}';
  }

  static String _formatDayName(DateTime d) {
    const days = [
      'lundi',
      'mardi',
      'mercredi',
      'jeudi',
      'vendredi',
      'samedi',
      'dimanche',
    ];
    return days[d.weekday - 1];
  }
}

class _DateStamp extends StatelessWidget {
  final String label;
  final Color accent;

  const _DateStamp({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.05,
      child: Container(
        width: 56,
        height: 56,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.12),
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 1.2),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.courierPrime(
            fontSize: 10,
            fontWeight: FontWeight.w700,
            height: 1.15,
            letterSpacing: 0.3,
            color: accent,
          ),
        ),
      ),
    );
  }
}

class _PersonalizeButton extends StatelessWidget {
  final VoidCallback onTap;

  const _PersonalizeButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.full),
        child: Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border, width: 0.8),
          ),
          child: Icon(
            Icons.tune_rounded,
            size: 16,
            color: colors.textSecondary,
            semanticLabel: 'Personnaliser ton Essentiel',
          ),
        ),
      ),
    );
  }
}

class _LeadTile extends StatelessWidget {
  final EssentielArticle article;
  final Color accent;
  final VoidCallback onTap;

  const _LeadTile({
    required this.article,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final themeAccent = _accentFor(article, accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Container(
          padding: const EdgeInsets.fromLTRB(
            FacteurSpacing.space3,
            FacteurSpacing.space3,
            FacteurSpacing.space3,
            FacteurSpacing.space3,
          ),
          decoration: BoxDecoration(
            color: themeAccent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(FacteurRadius.medium),
            border: Border(left: BorderSide(color: themeAccent, width: 3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SectionChip(label: article.sectionLabel, accent: themeAccent),
                  const Spacer(),
                  if (article.perspectiveCount > 1)
                    Text(
                      '+ ${article.perspectiveCount} sources',
                      style:
                          FacteurTypography.labelSmall(colors.textTertiary),
                    ),
                ],
              ),
              const SizedBox(height: FacteurSpacing.space2),
              Text(
                article.title,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: FacteurSpacing.space2),
              _SourceRow(article: article),
            ],
          ),
        ),
      ),
    );
  }
}

class _MediumTile extends StatelessWidget {
  final EssentielArticle article;
  final VoidCallback onTap;

  const _MediumTile({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final themeAccent = _accentFor(article, colors.sectionEssentiel);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _SectionChip(label: article.sectionLabel, accent: themeAccent),
                  const SizedBox(width: FacteurSpacing.space2),
                  Flexible(
                    child: Text(
                      article.sourceName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: FacteurTypography.labelSmall(colors.textTertiary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                article.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.fraunces(
                  fontSize: 14.5,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LightTile extends StatelessWidget {
  final EssentielArticle article;
  final VoidCallback onTap;

  const _LightTile({required this.article, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final themeAccent = _accentFor(article, colors.sectionEssentiel);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.small),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Container(
                width: 6,
                height: 6,
                decoration: BoxDecoration(
                  color: themeAccent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Text(
                article.sectionLabel.toUpperCase(),
                style: FacteurTypography.labelSmall(themeAccent).copyWith(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.6,
                ),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Text(
                '·',
                style: FacteurTypography.labelSmall(colors.textTertiary),
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: Text(
                  article.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: FacteurTypography.bodySmall(colors.textPrimary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionChip extends StatelessWidget {
  final String label;
  final Color accent;

  const _SectionChip({required this.label, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmSans(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
          color: accent,
        ),
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final EssentielArticle article;

  const _SourceRow({required this.article});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: colors.backgroundSecondary,
            shape: BoxShape.circle,
            border: Border.all(color: colors.border, width: 0.6),
          ),
          child: Text(
            article.sourceLetter,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: colors.textSecondary,
            ),
          ),
        ),
        const SizedBox(width: FacteurSpacing.space2),
        Flexible(
          child: Text(
            article.sourceName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: FacteurTypography.labelSmall(colors.textTertiary),
          ),
        ),
      ],
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Container(height: 0.6, color: colors.border);
  }
}

class _DottedDivider extends StatelessWidget {
  const _DottedDivider();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return LayoutBuilder(
      builder: (context, constraints) {
        final dashCount = (constraints.maxWidth / 4).floor();
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: List.generate(
            dashCount,
            (_) => Container(width: 2, height: 1, color: colors.border),
          ),
        );
      },
    );
  }
}

class _Footer extends StatelessWidget {
  final Color accent;
  final VoidCallback? onSkip;
  final VoidCallback? onExploreAll;

  const _Footer({required this.accent, this.onSkip, this.onExploreAll});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        if (onSkip != null)
          TextButton(
            onPressed: onSkip,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 32),
              foregroundColor: colors.textTertiary,
            ),
            child: Text(
              'Passer',
              style: FacteurTypography.labelLarge(colors.textTertiary),
            ),
          )
        else
          const SizedBox.shrink(),
        if (onExploreAll != null)
          Material(
            color: accent,
            borderRadius: BorderRadius.circular(FacteurRadius.pill),
            child: InkWell(
              onTap: onExploreAll,
              borderRadius: BorderRadius.circular(FacteurRadius.pill),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: FacteurSpacing.space4,
                  vertical: 8,
                ),
                child: Text(
                  'Tout explorer →',
                  style: GoogleFonts.dmSans(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Picks an accent color: theme slug first, then card-level kind fallback.
Color _accentFor(EssentielArticle article, Color fallback) {
  final slug = article.theme;
  if (slug != null && themeMap.containsKey(slug)) {
    return themeMap[slug]!.accent;
  }
  return fallback;
}
