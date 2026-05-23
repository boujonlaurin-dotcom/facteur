import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/theme.dart';
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
/// - "sticky-head" row : zone title ("Les Actus du jour" or "Explorer"),
/// - horizontal tabs with section dot, label, done strike-through, and
///   an underline tinted with the active section's accent,
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
  final String title;
  final bool showFilterBar;

  const StickyTabBar({
    super.key,
    required this.tabs,
    required this.activeIndex,
    required this.progress,
    required this.onTapTab,
    this.tabsController,
    this.title = 'Les Actus du jour',
    this.showFilterBar = false,
  });

  @override
  Widget build(BuildContext context) {
    return StickyBackdrop(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          StickyHead(title: title),
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
                gradient: const [
                  Color(0xFFD35400),
                  Color(0xFFC2185B),
                  Color(0xFF2C3E50),
                  Color(0xFF6C3483),
                ],
                glow: const Color.fromRGBO(211, 84, 0, 0.35),
                trackColor: const Color.fromRGBO(0, 0, 0, 0.06),
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
        ],
      ),
    );
  }
}

/// Top row of the sticky overlay — a single Fraunces label that names the
/// current zone of the Flux Continu screen.
class StickyHead extends StatelessWidget {
  final String title;

  const StickyHead({super.key, this.title = 'Les Actus du jour'});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Text(
            title,
            style: GoogleFonts.fraunces(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
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
      height: 44,
      child: ListView.separated(
        controller: controller,
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
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
    final dotColor = isActive
        ? tab.accent
        : (isDone ? colors.textTertiary : colors.textSecondary);
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 7, 12, 9),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 6),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: dotColor,
                  ),
                ),
                Text(
                  tab.label,
                  style: GoogleFonts.dmSans(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: labelColor,
                    decoration: isDone
                        ? TextDecoration.lineThrough
                        : TextDecoration.none,
                    decorationColor: labelColor,
                  ),
                ),
              ],
            ),
          ),
          if (isActive)
            Positioned(
              left: 8,
              right: 8,
              bottom: 0,
              height: 2,
              child: Container(
                decoration: BoxDecoration(
                  color: tab.accent,
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(2),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
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
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);
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
