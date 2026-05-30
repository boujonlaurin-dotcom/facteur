import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';
import '../models/weather_snapshot.dart';
import '../providers/weather_provider.dart';
import '../utils/theme_color_mapping.dart';

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
  final VoidCallback? onTapSeeAllDown;
  final VoidCallback? onTapExploreAll;

  const EssentielHiFiCard({
    super.key,
    required this.articles,
    required this.onTapArticle,
    required this.onTapPersonalize,
    this.onTapSeeAllDown,
    this.onTapExploreAll,
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
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space4,
          FacteurSpacing.space4,
          FacteurSpacing.space4,
          FacteurSpacing.space3,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Header(
              accent: accent,
              onTapPersonalize: onTapPersonalize,
            ),
            const SizedBox(height: FacteurSpacing.space4),
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
            const SizedBox(height: FacteurSpacing.space4),
            _Footer(
              accent: accent,
              onSeeAllDown: onTapSeeAllDown,
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

  const _Header({
    required this.accent,
    required this.onTapPersonalize,
  });

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
                'Tes 5 articles du jour, basé sur tes préférences',
                style: FacteurTypography.bodySmall(colors.textSecondary).copyWith(
                  height: 1.35,
                ),
              ),
            ],
          ),
        ),
      ],
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

    final Widget child;
    if (_showWeather) {
      final snapshot = ref.watch(weatherProvider).valueOrNull;
      if (snapshot != null) {
        child = GestureDetector(
          key: const ValueKey('weather'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _showWeather = false),
          child: _WeatherBadge(snapshot: snapshot),
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

    // Fixed slot: always 84×98 so the header never reflows when flipping.
    return SizedBox(
      width: 84,
      height: 98,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 320),
        switchInCurve: Curves.easeInOut,
        switchOutCurve: Curves.easeInOut,
        layoutBuilder: (current, previous) => Stack(
          alignment: Alignment.center,
          children: [...previous, if (current != null) current],
        ),
        transitionBuilder: (Widget child, Animation<double> animation) {
          final rotate = Tween<double>(begin: math.pi, end: 0.0)
              .animate(animation);
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

class _WeatherBadge extends StatelessWidget {
  final WeatherSnapshot snapshot;

  const _WeatherBadge({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SvgPicture.asset(
          'assets/images/weather/${snapshot.condition.assetName}.svg',
          width: 84,
          height: 84,
        ),
        RichText(
          text: TextSpan(
            style: GoogleFonts.courierPrime(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              height: 1.0,
            ),
            children: [
              TextSpan(
                text: '${snapshot.minC}°',
                style: TextStyle(color: colors.info),
              ),
              TextSpan(
                text: '/',
                style: TextStyle(color: colors.textSecondary),
              ),
              TextSpan(
                text: '${snapshot.maxC}°',
                style: TextStyle(color: colors.error),
              ),
            ],
          ),
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
    return Container(
      width: 60,
      height: 60,
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
              fontSize: 18,
              fontWeight: FontWeight.w700,
              height: 1.0,
              color: accent,
            ),
          ),
          Text(
            month,
            style: GoogleFonts.courierPrime(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              height: 1.0,
              letterSpacing: 0.8,
              color: accent,
            ),
          ),
        ],
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
        child: Container(
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
                      style: FacteurTypography.labelSmall(colors.textTertiary),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                article.title,
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
              decoration: BoxDecoration(
                color: accent,
                shape: BoxShape.circle,
              ),
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
    final avatarBg =
        isFollowed ? accent.withValues(alpha: 0.18) : colors.backgroundSecondary;
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

class _Hairline extends StatelessWidget {
  const _Hairline();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Container(
      height: 0.6,
      color: colors.border.withValues(alpha: 0.20),
    );
  }
}

class _Footer extends StatelessWidget {
  final Color accent;
  final VoidCallback? onSeeAllDown;
  final VoidCallback? onExploreAll;

  const _Footer({required this.accent, this.onSeeAllDown, this.onExploreAll});

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).extension<FacteurColors>()!;
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        if (onSeeAllDown != null) ...[
          TextButton(
            onPressed: onSeeAllDown,
            style: TextButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              minimumSize: const Size(0, 32),
              foregroundColor: colors.textTertiary,
            ),
            child: Text(
              'Tous mes articles ↓',
              style: FacteurTypography.labelLarge(colors.textTertiary),
            ),
          ),
          const SizedBox(width: FacteurSpacing.space2),
        ],
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
                  'Tout l’essentiel',
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

