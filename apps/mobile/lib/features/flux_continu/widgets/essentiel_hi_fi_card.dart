import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';
import '../models/weather_snapshot.dart';
import '../providers/weather_provider.dart';
import '../utils/theme_color_mapping.dart';
import 'weather_condition_icon.dart';
import 'weather_detail_sheet.dart';

/// Carte hi-fi unique "L'Essentiel du jour".
///
/// Présente jusqu'à 5 articles transversaux du jour :
///   - `articles[0]` → lead (fond teinté, bord gauche accent)
///   - `articles[1..2]` → médiums (filets fins)
///   - `articles[3..4]` → lights (filet pointillé, une ligne tronquée)
class EssentielHiFiCard extends StatelessWidget {
  final List<EssentielArticle> articles;
  final void Function(EssentielArticle article) onTapArticle;
  final VoidCallback onTapPersonalize;

  const EssentielHiFiCard({
    super.key,
    required this.articles,
    required this.onTapArticle,
    required this.onTapPersonalize,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final accent = colors.sectionEssentiel;

    final lead = articles.isNotEmpty ? articles.first : null;
    final remaining = articles.length > 1
        ? articles.sublist(1, articles.length > 5 ? 5 : articles.length)
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
        // Compaction « cartes ≤ écran » : top resserré space4→space3 pour
        // gagner ~4px sans toucher la pastille date/météo (choix PO).
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space4,
          FacteurSpacing.space3,
          FacteurSpacing.space4,
          FacteurSpacing.space3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(accent: accent, onTapPersonalize: onTapPersonalize),
            // Compaction : gap header→lead resserré space4→space3.
            const SizedBox(height: FacteurSpacing.space3),
            if (lead != null)
              _LeadTile(
                article: lead,
                accent: accent,
                onTap: () => onTapArticle(lead),
              ),
            for (final a in remaining) ...[
              const SizedBox(height: FacteurSpacing.space2),
              const _Hairline(),
              const SizedBox(height: FacteurSpacing.space2),
              _MediumTile(article: a, onTap: () => onTapArticle(a)),
            ],
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

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        _HeaderBadge(accent: accent),
        const SizedBox(width: FacteurSpacing.space3),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _HeaderAccentDash(accent: accent),
              const SizedBox(height: 7),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Text(
                      'Ton Essentiel',
                      style: GoogleFonts.fraunces(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        height: 1.2,
                        color: colors.textPrimary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: FacteurSpacing.space2),
                  _PersonalizeButton(onTap: onTapPersonalize),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                '5 articles du jour, basé sur tes intérêts',
                style: FacteurTypography.bodySmall(
                  colors.textSecondary,
                ).copyWith(height: 1.35),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _HeaderAccentDash extends StatelessWidget {
  final Color accent;

  const _HeaderAccentDash({required this.accent});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        width: 30,
        height: 3,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.82),
          borderRadius: BorderRadius.circular(999),
        ),
      ),
    );
  }
}

String _monthAbbrev(int m) {
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
  return months[m - 1];
}

class _HeaderBadge extends ConsumerStatefulWidget {
  final Color accent;

  const _HeaderBadge({required this.accent});

  @override
  ConsumerState<_HeaderBadge> createState() => _HeaderBadgeState();
}

class _HeaderBadgeState extends ConsumerState<_HeaderBadge> {
  bool _showWeather = false;
  Timer? _flipTimer;

  @override
  void initState() {
    super.initState();
    _flipTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showWeather = true);
    });
  }

  @override
  void dispose() {
    _flipTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    // Always watch so the fetch starts on mount and any update triggers a rebuild.
    final forecast = ref.watch(weatherProvider).valueOrNull;

    final Widget child;
    if (_showWeather && forecast != null) {
      child = GestureDetector(
        key: const ValueKey('weather'),
        behavior: HitTestBehavior.opaque,
        onTap: () => showWeatherDetailSheet(context),
        child: _WeatherBadge(forecast: forecast),
      );
    } else {
      child = GestureDetector(
        key: const ValueKey('date'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showWeather = true),
        child: _DateStamp(
          day: now.day,
          month: _monthAbbrev(now.month),
          accent: widget.accent,
        ),
      );
    }

    // Fixed slot: the header never reflows when flipping between date/weather.
    return SizedBox(
      width: 110,
      height: 132,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (Widget child, Animation<double> animation) {
          final rotate = Tween<double>(
            begin: math.pi,
            end: 0.0,
          ).animate(animation);
          return AnimatedBuilder(
            animation: rotate,
            builder: (context, c) {
              final isFront = animation.value > 0.5;
              return Transform(
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0015)
                  ..rotateY(rotate.value),
                alignment: Alignment.center,
                child: Opacity(opacity: isFront ? 1 : 0, child: c),
              );
            },
            child: child,
          );
        },
        child: child,
      ),
    );
  }
}

/// Bloc météo compact du header : icône condition, min/max, et un indice
/// discret signalant qu'un tap ouvre la modal détaillée 5 jours.
class _WeatherBadge extends StatefulWidget {
  final WeatherForecast forecast;

  const _WeatherBadge({required this.forecast});

  @override
  State<_WeatherBadge> createState() => _WeatherBadgeState();
}

class _WeatherBadgeState extends State<_WeatherBadge>
    with SingleTickerProviderStateMixin {
  late final AnimationController _temperatureController;
  late final Animation<double> _temperatureScale;

  @override
  void initState() {
    super.initState();
    _temperatureController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 450),
    );
    _temperatureScale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(
          begin: 0.94,
          end: 1.06,
        ).chain(CurveTween(curve: Curves.easeOutCubic)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween(
          begin: 1.06,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeInOutCubic)),
        weight: 45,
      ),
    ]).animate(_temperatureController);
    _temperatureController.forward();
  }

  @override
  void dispose() {
    _temperatureController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        WeatherConditionIcon(
          condition: widget.forecast.condition,
          size: 82,
          badgeSize: 30,
          emojiSize: 18,
          badgeInset: 4,
        ),
        ScaleTransition(
          key: const ValueKey('weather_temperatures'),
          scale: _temperatureScale,
          child: RichText(
            text: TextSpan(
              style: GoogleFonts.courierPrime(
                fontSize: 17,
                fontWeight: FontWeight.w700,
                height: 1.0,
              ),
              children: [
                TextSpan(
                  text: '${widget.forecast.minC}°',
                  style: TextStyle(color: colors.info),
                ),
                TextSpan(
                  text: '/',
                  style: TextStyle(color: colors.textSecondary),
                ),
                TextSpan(
                  text: '${widget.forecast.maxC}°',
                  style: TextStyle(color: colors.error),
                ),
              ],
            ),
          ),
        ),
        Icon(
          Icons.keyboard_arrow_down_rounded,
          size: 16,
          color: colors.textTertiary,
          semanticLabel: 'Voir la météo détaillée',
        ),
      ],
    );
  }
}

class _DateStamp extends StatelessWidget {
  final int day;
  final String month;
  final Color accent;

  const _DateStamp({
    required this.day,
    required this.month,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 68,
          height: 68,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.transparent,
            shape: BoxShape.circle,
            border: Border.all(color: accent, width: 0.7),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                day.toString().padLeft(2, '0'),
                style: GoogleFonts.courierPrime(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  color: accent,
                ),
              ),
              Text(
                month,
                style: GoogleFonts.courierPrime(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                  letterSpacing: 0.8,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Météo',
              style: GoogleFonts.courierPrime(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                height: 1.0,
                letterSpacing: 0.8,
                color: colors.textTertiary.withValues(alpha: 0.76),
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.keyboard_return_rounded,
              size: 11,
              color: colors.textTertiary.withValues(alpha: 0.72),
              semanticLabel: 'Retourner vers la météo',
            ),
          ],
        ),
      ],
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
          width: 26,
          height: 26,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: colors.border, width: 0.8),
          ),
          child: Icon(
            Icons.tune_rounded,
            size: 13,
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
    final chipAccent = _accentFor(article, accent);
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        // Lu : grise la tuile (0.6) + coche verte, comme les autres sections
        // (cf. flux_continu_article_card.dart). Le badge est inclus dans
        // l'Opacity pour s'estomper de concert avec le contenu.
        child: Opacity(
          opacity: article.isRead ? 0.6 : 1.0,
          child: Stack(
            children: [
              Container(
                padding: const EdgeInsets.fromLTRB(
                  FacteurSpacing.space3,
                  FacteurSpacing.space3,
                  FacteurSpacing.space3,
                  FacteurSpacing.space3,
                ),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(FacteurRadius.medium),
                  border: Border(left: BorderSide(color: accent, width: 3)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        if (article.isActuDuJour)
                          _ActuBadge(
                            accent: chipAccent,
                            overrideBackground: colors.sectionEssentiel,
                          ),
                        _SectionChip(
                          label: _sectionLabelFor(article),
                          accent: chipAccent,
                          showFollowed: article.isFollowedTopic,
                        ),
                      ],
                    ),
                    const SizedBox(height: FacteurSpacing.space2),
                    Text(
                      article.title,
                      // Compaction « cartes ≤ écran » : plafond 5→4 lignes pour
                      // borner la hauteur du lead (cohérent avec section_fit).
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fraunces(
                        fontSize: 19,
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: FacteurSpacing.space2),
                    _SourceRow(article: article, accent: chipAccent),
                  ],
                ),
              ),
              if (article.isRead)
                Positioned(
                  top: 8,
                  right: 8,
                  child: _ReadCheckBadge(color: colors.success),
                ),
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
        // Lu : grise la tuile (0.6) + petite coche verte (cf. _LeadTile).
        child: Opacity(
          opacity: article.isRead ? 0.6 : 1.0,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _SectionChip(
                          label: _sectionLabelFor(article),
                          accent: themeAccent,
                          showFollowed: article.isFollowedTopic,
                        ),
                        const SizedBox(width: FacteurSpacing.space2),
                        Flexible(
                          child: Text(
                            article.sourceName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: FacteurTypography.labelSmall(
                              colors.textTertiary,
                            ),
                          ),
                        ),
                        // Réserve l'espace de la coche pour qu'elle ne
                        // chevauche pas la source ellipsée.
                        if (article.isRead) const SizedBox(width: 22),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      article.title,
                      // Compaction « cartes ≤ écran » : plafond 4→3 lignes.
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.fraunces(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ),
              if (article.isRead)
                Positioned(
                  top: 0,
                  right: 0,
                  child: _ReadCheckBadge(color: colors.success, size: 18),
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
  final bool showFollowed;

  const _SectionChip({
    required this.label,
    required this.accent,
    this.showFollowed = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showFollowed) ...[
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
          ],
          Text(
            label,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pastille "Actu du jour" affichée à côté du chip section dans le lead.
/// [overrideBackground] permet de forcer la couleur orange Essentiel quel
/// que soit le thème de l'article (sinon `accent` est utilisé).
class _ActuBadge extends StatelessWidget {
  final Color accent;
  final Color? overrideBackground;

  const _ActuBadge({required this.accent, this.overrideBackground});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: overrideBackground ?? accent,
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Actu du jour',
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.4,
              color: Colors.white,
            ),
          ),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  final EssentielArticle article;
  final Color accent;

  const _SourceRow({required this.article, required this.accent});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    final isFollowed = article.isFollowedSource;
    final avatarBg = isFollowed
        ? accent.withValues(alpha: 0.18)
        : colors.backgroundSecondary;
    final avatarBorder = isFollowed ? accent : colors.border;
    final avatarTextColor = isFollowed ? accent : colors.textSecondary;
    return Row(
      children: [
        Container(
          width: 20,
          height: 20,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: avatarBg,
            shape: BoxShape.circle,
            border: Border.all(color: avatarBorder, width: 0.8),
          ),
          child: Text(
            article.sourceLetter,
            style: GoogleFonts.dmSans(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: avatarTextColor,
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

/// Coche « lu » verte, reproduite à l'identique du motif de
/// `flux_continu_article_card.dart` pour une cohérence visuelle entre la carte
/// Essentiel et les cartes des autres sections. [size] permet une coche plus
/// compacte sur les tuiles médiums.
class _ReadCheckBadge extends StatelessWidget {
  final Color color;
  final double size;

  const _ReadCheckBadge({required this.color, this.size = 22});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
            blurRadius: 4,
            offset: const Offset(0, 1),
          ),
        ],
      ),
      alignment: Alignment.center,
      child: Icon(
        PhosphorIcons.check(PhosphorIconsStyle.bold),
        size: size * 0.55,
        color: Colors.white,
      ),
    );
  }
}

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Container(height: 0.6, color: colors.border.withValues(alpha: 0.20));
  }
}

/// Looks up an entry in [themeMap] by article theme slug and extracts [selector].
/// Returns null when the slug is absent or not in the map.
T? _themeMapLookup<T>(String? slug, T Function(ThemeVisual) selector) {
  if (slug != null && themeMap.containsKey(slug)) {
    return selector(themeMap[slug]!);
  }
  return null;
}

/// Picks an accent color: theme slug first, then card-level kind fallback.
Color _accentFor(EssentielArticle article, Color fallback) =>
    _themeMapLookup(article.theme, (e) => e.accent) ?? fallback;

/// Resolves the section label rendered next to each article in the hi-fi card.
///
/// Prefers the stable client-side [themeMap] over the backend `section_label`,
/// which is often empty or non-canonical (e.g. carries the source name).
String _sectionLabelFor(EssentielArticle article) {
  if (_themeMapLookup(article.theme, (e) => e.label) case final label?) {
    return label;
  }
  final raw = article.sectionLabel.trim();
  if (raw.isNotEmpty) return raw;
  return 'Actus';
}
