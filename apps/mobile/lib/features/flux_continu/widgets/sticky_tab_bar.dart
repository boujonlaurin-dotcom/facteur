import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
import '../../feed/providers/feed_provider.dart';
import '../../feed/widgets/feed_filter_bar.dart';
import 'sticky_backdrop.dart';

/// Lightweight descriptor for a sticky tab. Used by [StickyTabBar] so the
/// sticky overlay can mix real Flux sections with virtual entries (e.g.
/// "Explorer") without leaking widget-only state into the section sealed
/// hierarchy.
class StickyTab {
  final String label;
  final Color accent;

  const StickyTab({required this.label, required this.accent});
}

/// Sticky tab bar revealed once the user scrolls past the AppBar threshold.
///
/// Layout per V6 maquette :
/// - parchment-tinted backdrop with a 14px blur (saturate 140%),
/// - horizontal tabs with a label, a check icon when the tab is done
///   (replaces the legacy strike-through, per PO feedback hotfix 2026-05-23 —
///   "lu = checked, pas barré"), and a marker-style highlight on the active
///   tab's label text (calque du highlight "Couverture médiatique" — cf.
///   DiffTitle ; remplace l'ancien wash pleine-chip + le point),
/// - 4-px progress track with a 4-stop gradient fill (essentiel → bonnes
///   → veille1 → veille2) and a soft accent glow,
/// - when [showFilterBar] is true (Explorer mode), [FeedFilterBar] is
///   inserted below the tabs so the filter chips morph in under the same
///   parchment surface rather than swapping the whole sticky.
class StickyTabBar extends StatelessWidget {
  final List<StickyTab> tabs;
  final int activeIndex;
  final double progress;
  final ValueChanged<int> onTapTab;
  final ScrollController? tabsController;
  final bool showFilterBar;

  const StickyTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.progress,
    required this.onTapTab,
    this.tabsController,
    this.showFilterBar = false,
  });

  @override
  Widget build(BuildContext context) {
    final trackColor = context.isDarkMode
        ? const Color.fromRGBO(255, 255, 255, 0.08)
        : const Color.fromRGBO(0, 0, 0, 0.06);

    return StickyBackdrop(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _TabsRow(
            tabs: tabs,
            activeIndex: activeIndex,
            onTapTab: onTapTab,
            controller: tabsController,
          ),
          SizedBox(
            height: 4,
            child: CustomPaint(
              painter: _ProgressPainter(
                progress: progress.clamp(0.0, 1.0),
                // Désaturation forte (PO 2026-06) : on garde l'ordre/identité
                // chromatique (rouge → ocre → bleu → sauge) mais saturation
                // abaissée ~65 % + luminosité remontée vers des tons pastel,
                // pour que la barre ne tire plus l'œil. Valeurs ajustables à
                // l'œil sur device.
                gradient: const [
                  Color(0xFFB08585), // rose poussiéreux (ex B71C1C)
                  Color(0xFFC9A878), // sable / ocre doux (ex F57F17)
                  Color(0xFF7E96B5), // bleu ardoise atténué (ex 1565C0)
                  Color(0xFF7FA39B), // sauge grisée (ex 00695C)
                ],
                // Halo fortement réduit (alpha 0.35 → 0.10) et accordé au
                // nouveau rouge désaturé : présence à peine perceptible.
                glow: const Color.fromRGBO(176, 133, 133, 0.10),
                trackColor: trackColor,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: showFilterBar
                ? const Padding(
                    padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
                    child: FeedFilterBar(),
                  )
                : const SizedBox(width: double.infinity),
          ),
          const _FeedRefreshIndicatorStrip(),
        ],
      ),
    );
  }
}

/// 2 px progress strip wired to [feedRefreshingProvider]. Sits flush at the
/// bottom of the sticky bar so the user gets immediate feedback that a
/// filter / search change triggered a fetch in flight.
class _FeedRefreshIndicatorStrip extends ConsumerWidget {
  const _FeedRefreshIndicatorStrip();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final refreshing = ref.watch(feedRefreshingProvider);
    final colors = context.facteurColors;
    return SizedBox(
      height: 2,
      child: refreshing
          ? LinearProgressIndicator(
              minHeight: 2,
              backgroundColor: Colors.transparent,
              color: colors.primary,
            )
          : const SizedBox.shrink(),
    );
  }
}

class _TabsRow extends StatelessWidget {
  final List<StickyTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTapTab;
  final ScrollController? controller;

  const _TabsRow({
    required this.tabs,
    required this.activeIndex,
    required this.onTapTab,
    this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, i) {
          return _Tab(
            tab: tabs[i],
            isActive: i == activeIndex,
            isDone: i < activeIndex,
            onTap: () => onTapTab(i),
          );
        },
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final StickyTab tab;
  final bool isActive;
  final bool isDone;
  final VoidCallback onTap;

  const _Tab({
    required this.tab,
    required this.isActive,
    required this.isDone,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final Color labelColor;
    if (isActive) {
      labelColor = colors.textPrimary;
    } else if (isDone) {
      labelColor = colors.textTertiary;
    } else {
      labelColor = colors.textSecondary;
    }
    // Active tab is signaled by a felt-tip marker stroke painted **behind the
    // label text only** (calque du highlight "Couverture médiatique" — cf.
    // DiffTitle), replacing the legacy full-chip wash + leading dot. The marker
    // tint derives from the tab's own accent so each thematic section keeps its
    // hue ; le trait est légèrement incliné, à extrémités inégales et opacité
    // douce pour lire comme un tracé manuel (cf. [_MarkerHighlight]).
    const radius = BorderRadius.all(Radius.circular(FacteurRadius.small));
    final label = Text(
      tab.label,
      style: GoogleFonts.dmSans(
        fontSize: 16,
        fontWeight: FontWeight.w600,
        color: labelColor,
      ),
    );
    return InkWell(
      onTap: onTap,
      borderRadius: radius,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 5, 12, 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isActive)
              CustomPaint(
                painter: _MarkerHighlight(color: tab.accent),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: label,
                ),
              )
            else
              label,
            if (isDone) ...[
              const SizedBox(width: 4),
              Icon(
                Icons.check_rounded,
                size: 18,
                color: labelColor,
                semanticLabel: 'lu',
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Felt-tip "surligneur" stroke painted behind a tab label. Reads as a
/// hand-drawn highlighter pass rather than a flat rounded chip :
/// - a band covering only the lower ~62 % of the text height, anchored to the
///   baseline so ascenders/descenders peek out,
/// - a slight ~-1.2° tilt,
/// - softly uneven rounded caps for the "movement / manual trace" feel,
/// - reduced opacity (0.13) with a second translucent pass (0.07) layered near
///   the baseline to keep the felt density restrained.
class _MarkerHighlight extends CustomPainter {
  final Color color;

  const _MarkerHighlight({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;
    final bandHeight = size.height * 0.62;
    final top = size.height - bandHeight; // anchored to the baseline
    final rect = Rect.fromLTWH(0, top, size.width, bandHeight);

    canvas.save();
    // Tilt around the band centre so the whole stroke leans slightly.
    canvas.translate(size.width / 2, size.height / 2);
    canvas.rotate(-1.2 * math.pi / 180);
    canvas.translate(-size.width / 2, -size.height / 2);

    // Uneven caps, kept subtle so the marker feels hand-drawn but steady.
    final base = RRect.fromRectAndCorners(
      rect,
      topLeft: Radius.circular(bandHeight * 0.38),
      bottomLeft: Radius.circular(bandHeight * 0.36),
      topRight: Radius.circular(bandHeight * 0.48),
      bottomRight: Radius.circular(bandHeight * 0.52),
    );
    canvas.drawRRect(base, Paint()..color = color.withValues(alpha: 0.13));

    // Second pass, inset toward the baseline, adds the denser felt core.
    final core = Rect.fromLTWH(
      rect.left + size.width * 0.06,
      rect.top + bandHeight * 0.30,
      size.width * 0.88,
      bandHeight * 0.66,
    );
    final coreRRect = RRect.fromRectAndRadius(
      core,
      Radius.circular(bandHeight * 0.4),
    );
    canvas.drawRRect(coreRRect, Paint()..color = color.withValues(alpha: 0.07));

    canvas.restore();
  }

  @override
  bool shouldRepaint(_MarkerHighlight old) => old.color != color;
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final List<Color> gradient;
  final Color glow;
  final Color trackColor;

  _ProgressPainter({
    required this.progress,
    required this.gradient,
    required this.glow,
    required this.trackColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final fullRect = Offset.zero & size;
    final trackPaint = Paint()..color = trackColor;
    canvas.drawRect(fullRect, trackPaint);

    if (progress <= 0) return;
    final clipped = Rect.fromLTWH(0, 0, size.width * progress, size.height);
    final glowPaint = Paint()
      ..color = glow
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5);
    canvas.drawRect(clipped, glowPaint);
    final fillPaint = Paint()
      ..shader = LinearGradient(
        colors: gradient,
        stops: const [0.0, 0.4, 0.7, 1.0],
      ).createShader(fullRect);
    canvas.drawRect(clipped, fillPaint);
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress ||
      old.gradient != gradient ||
      old.glow != glow ||
      old.trackColor != trackColor;
}
