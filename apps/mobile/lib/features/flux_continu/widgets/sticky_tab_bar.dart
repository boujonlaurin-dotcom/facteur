import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  /// Clé d'ordre Tournée (`theme:`/`source:`/`essentiel`/`bonnes`/`veille`)
  /// quand l'onglet correspond à une section **réordonnable** ; `null` sinon
  /// (carte héros Essentiel, Mot du jour, Citation, Fin de tournée, « Pour
  /// toi », alertes). Non-null ⇒ l'onglet peut être soulevé au long-press dans
  /// le header et sert de clé pour la persistance de l'ordre.
  final String? orderKey;

  const StickyTab({required this.label, required this.accent, this.orderKey});
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
/// - 4-px **segmented** progress track — one rounded pip per section (done /
///   current / upcoming), driven by [activeIndex], so the bar reads as discrete
///   « pages » matching the section snap rather than a continuous gauge,
/// - when [showFilterBar] is true (Explorer mode), [FeedFilterBar] is
///   inserted below the tabs so the favorite-topic tabs sit under the same
///   parchment surface rather than swapping the whole sticky.
class StickyTabBar extends StatelessWidget {
  final List<StickyTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTapTab;
  final ScrollController? tabsController;
  final bool showFilterBar;

  /// Réordre par drag long-press d'un onglet. `null` ⇒ rangée non réordonnable
  /// (comportement historique). Reçoit les index bruts de
  /// `ReorderableListView` (`newIndex` exprimé dans l'espace d'insertion) ; le
  /// remappage vers les clés d'ordre est fait par l'appelant.
  final void Function(int oldIndex, int newIndex)? onReorder;

  /// Bornes du drag, pour geler l'auto-align et le suivi de section actif tant
  /// qu'un onglet est soulevé.
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const StickyTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.onTapTab,
    this.tabsController,
    this.showFilterBar = false,
    this.onReorder,
    this.onDragStart,
    this.onDragEnd,
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
            onReorder: onReorder,
            onDragStart: onDragStart,
            onDragEnd: onDragEnd,
          ),
          SizedBox(
            height: 4,
            child: CustomPaint(
              painter: _ProgressPainter(
                // Track segmenté (un pip par section) : modèle mental « pages »
                // qui correspond au snap discret, au lieu d'une jauge continue.
                segmentCount: tabs.length,
                currentIndex: activeIndex,
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

/// Rangée d'onglets horizontale. Quand [onReorder] est fourni **et** qu'au
/// moins deux onglets portent une `orderKey`, la rangée devient un
/// `ReorderableListView` horizontal : un long-press (~900 ms) sur un onglet
/// réordonnable le soulève, le glissement le repositionne. Les onglets figés
/// (héros, Mot du jour, Citation, Fin de tournée) ne portent pas de listener de
/// drag — ils sont donc non saisissables « gratuitement » et servent de bornes.
class _TabsRow extends StatefulWidget {
  final List<StickyTab> tabs;
  final int activeIndex;
  final ValueChanged<int> onTapTab;
  final ScrollController? controller;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final VoidCallback? onDragStart;
  final VoidCallback? onDragEnd;

  const _TabsRow({
    required this.tabs,
    required this.activeIndex,
    required this.onTapTab,
    this.controller,
    this.onReorder,
    this.onDragStart,
    this.onDragEnd,
  });

  @override
  State<_TabsRow> createState() => _TabsRowState();
}

class _TabsRowState extends State<_TabsRow> {
  /// Un onglet est soulevé. Pilote l'atténuation des zones figées.
  bool _dragging = false;

  /// Un réordre n'a de sens qu'avec ≥2 onglets déplaçables (sinon le seul
  /// onglet mobile n'a nulle part où aller, et le clamp le renverrait en queue).
  bool get _reorderEnabled {
    if (widget.onReorder == null) return false;
    var count = 0;
    for (final t in widget.tabs) {
      if (t.orderKey != null && ++count >= 2) return true;
    }
    return false;
  }

  void _setDragging(bool value) {
    if (_dragging == value) return;
    setState(() => _dragging = value);
  }

  @override
  Widget build(BuildContext context) {
    // Compaction « cartes ≤ écran » : rangée d'onglets 48→44 (sync avec
    // `_kStickyBarHeight` côté écran, qui alimente budget de fit ET snap).
    const height = 44.0;
    // Padding latéral 12 - 1 : l'espacement inter-onglets (ex-`separatorBuilder`
    // de 2px) est désormais porté par chaque item (1px de chaque côté), car
    // `ReorderableListView` n'accepte pas de séparateurs.
    const padding = EdgeInsets.fromLTRB(11, 2, 11, 6);

    if (!_reorderEnabled) {
      return SizedBox(
        height: height,
        child: ListView.builder(
          controller: widget.controller,
          scrollDirection: Axis.horizontal,
          padding: padding,
          itemCount: widget.tabs.length,
          itemBuilder: (context, i) => _buildTab(i, draggable: false),
        ),
      );
    }

    return SizedBox(
      height: height,
      child: ReorderableListView.builder(
        scrollController: widget.controller,
        scrollDirection: Axis.horizontal,
        padding: padding,
        // Les poignées par défaut rendraient *tous* les onglets déplaçables ;
        // on pose le listener nous-mêmes, uniquement sur les réordonnables.
        buildDefaultDragHandles: false,
        proxyDecorator: _proxyDecorator,
        itemCount: widget.tabs.length,
        onReorderStart: (_) {
          HapticFeedback.mediumImpact();
          _setDragging(true);
          widget.onDragStart?.call();
        },
        onReorderEnd: (_) {
          HapticFeedback.selectionClick();
          _setDragging(false);
          widget.onDragEnd?.call();
        },
        onReorder: (oldIndex, newIndex) =>
            widget.onReorder!(oldIndex, newIndex),
        itemBuilder: (context, i) => _buildTab(i, draggable: true),
      ),
    );
  }

  Widget _buildTab(int i, {required bool draggable}) {
    final tab = widget.tabs[i];
    final reorderable = draggable && tab.orderKey != null;
    Widget child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 1),
      child: _Tab(
        tab: tab,
        isActive: i == widget.activeIndex,
        isDone: i < widget.activeIndex,
        onTap: () => widget.onTapTab(i),
      ),
    );
    if (_dragging && !reorderable) {
      // Zones figées atténuées pendant le drag : lisible sans icône cadenas
      // (minimalisme du « moment de fermeture »).
      child = Opacity(opacity: 0.5, child: child);
    }
    return KeyedSubtree(
      // Clé stable : la clé d'ordre pour les réordonnables (invariante au
      // déplacement), la position + le libellé pour les onglets figés.
      key: ValueKey(tab.orderKey ?? 'fixed:$i:${tab.label}'),
      child: reorderable
          ? _LongPressReorderListener(index: i, child: child)
          : child,
    );
  }

  /// Proxy « soulevé » : léger agrandissement + ombre portée + fond opaque,
  /// pour que l'onglet se détache du backdrop parchemin pendant le drag.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    final colors = context.facteurColors;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, inner) {
        // Mêmes courbe / amplitude que le `_DragProxy` de la sheet
        // « Composer ma Tournée » : le soulèvement se lit pareil aux deux
        // points d'entrée.
        final t = Curves.easeInOut.transform(animation.value.clamp(0.0, 1.0));
        return Transform.scale(
          scale: 1 + 0.03 * t,
          child: Container(
            decoration: BoxDecoration(
              color: Color.lerp(
                Colors.transparent,
                colors.backgroundPrimary,
                t,
              ),
              borderRadius: const BorderRadius.all(
                Radius.circular(FacteurRadius.small),
              ),
              boxShadow: [
                BoxShadow(
                  color: Color.fromRGBO(0, 0, 0, 0.18 * t),
                  blurRadius: 12 * t,
                  offset: Offset(0, 4 * t),
                ),
              ],
            ),
            // Le proxy est rendu dans l'Overlay, hors de l'arbre Material de
            // la page : sans ce Material, l'InkWell de `_Tab` casse.
            child: Material(type: MaterialType.transparency, child: inner),
          ),
        );
      },
      child: child,
    );
  }
}

/// `ReorderableDragStartListener` à délai long (~900 ms) : le défaut de
/// `ReorderableDelayedDragStartListener` est de 500 ms et non paramétrable, ce
/// qui entre en concurrence avec le scroll horizontal de la rangée. Le
/// `DelayedMultiDragGestureRecognizer` annule aussi au moindre mouvement
/// pendant le hold ⇒ un swipe reste un scroll, un tap reste une navigation.
class _LongPressReorderListener extends ReorderableDragStartListener {
  const _LongPressReorderListener({
    required super.child,
    required super.index,
  });

  @override
  MultiDragGestureRecognizer createRecognizer() =>
      DelayedMultiDragGestureRecognizer(
        debugOwner: this,
        delay: const Duration(milliseconds: 900),
      );
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

/// Segmented progress track — one rounded pip per section, mirroring the
/// discrete section-snap ("pages") instead of a continuous gauge. State is read
/// from [currentIndex] (same source as the tabs' `isDone` check, so the bar and
/// the checkmarks never disagree):
/// - `i < currentIndex` → **done**: filled with the section's own desaturated
///   identity colour (preserves the per-section hue ordering);
/// - `i == currentIndex` → **current**: full-opacity segment colour + the soft
///   accent [glow], scoped to that segment;
/// - `i > currentIndex` → **upcoming**: the muted [trackColor].
///
/// The current segment is filled whole (no sub-fill by scroll fraction) for
/// maximal discrete reading, so a repaint is only needed when the active
/// section, the count, or the colours change.
class _ProgressPainter extends CustomPainter {
  final int segmentCount;
  final int currentIndex;
  final List<Color> gradient;
  final Color glow;
  final Color trackColor;

  _ProgressPainter({
    required this.segmentCount,
    required this.currentIndex,
    required this.gradient,
    required this.glow,
    required this.trackColor,
  });

  /// ~3 px gutter between pips so they read as distinct pages.
  static const double _gutter = 3.0;

  @override
  void paint(Canvas canvas, Size size) {
    if (segmentCount <= 0) return;
    final segWidth =
        (size.width - _gutter * (segmentCount - 1)) / segmentCount;
    // Degenerate (too many sections for the width): fall back to a plain track
    // rather than painting negative-width pips.
    if (segWidth <= 0) {
      canvas.drawRect(Offset.zero & size, Paint()..color = trackColor);
      return;
    }
    final radius = Radius.circular(size.height / 2);
    for (var i = 0; i < segmentCount; i++) {
      final left = i * (segWidth + _gutter);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromLTWH(left, 0, segWidth, size.height),
        radius,
      );
      if (i == currentIndex) {
        canvas.drawRRect(
          rrect,
          Paint()
            ..color = glow
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5),
        );
        canvas.drawRRect(rrect, Paint()..color = _segmentColor(i));
      } else if (i < currentIndex) {
        canvas.drawRRect(rrect, Paint()..color = _segmentColor(i));
      } else {
        canvas.drawRRect(rrect, Paint()..color = trackColor);
      }
    }
  }

  /// Maps a segment to a colour along [gradient], so each section keeps its
  /// chromatic identity even when the section count differs from the number of
  /// gradient stops (lerped across the stops).
  Color _segmentColor(int i) {
    if (gradient.isEmpty) return trackColor;
    if (gradient.length == 1 || segmentCount == 1) return gradient.first;
    final scaled = (i / (segmentCount - 1)) * (gradient.length - 1);
    final lo = scaled.floor().clamp(0, gradient.length - 1);
    final hi = math.min(lo + 1, gradient.length - 1);
    return Color.lerp(gradient[lo], gradient[hi], scaled - lo) ?? gradient[lo];
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.segmentCount != segmentCount ||
      old.currentIndex != currentIndex ||
      old.gradient != gradient ||
      old.glow != glow ||
      old.trackColor != trackColor;
}
