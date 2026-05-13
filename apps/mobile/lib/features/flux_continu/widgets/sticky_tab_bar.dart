import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';

/// Sticky tab bar revealed once the user scrolls past the AppBar threshold.
///
/// Layout per V6 maquette :
/// - parchment-tinted backdrop with a 14px blur (saturate 140%),
/// - "sticky-head" row : "Bonne tournée" + fire icon (no progress count
///   in V6 — the textual progress was dropped),
/// - horizontal tabs with section dot, label, done strike-through, and
///   an underline tinted with the active section's accent,
/// - 4-px progress track with a 4-stop gradient fill (essentiel → bonnes
///   → veille1 → veille2) and a soft accent glow.
class StickyTabBar extends StatelessWidget {
  final List<FluxSection> sections;
  final int activeIndex;
  final double progress;
  final ValueChanged<int> onTapTab;

  const StickyTabBar({
    super.key,
    required this.sections,
    required this.activeIndex,
    required this.progress,
    required this.onTapTab,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          decoration: BoxDecoration(
            color: const Color.fromRGBO(242, 232, 213, 0.92),
            border: const Border(
              bottom: BorderSide(
                color: Color.fromRGBO(0, 0, 0, 0.06),
                width: 1,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.18),
                blurRadius: 12,
                spreadRadius: -6,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: SafeArea(
            bottom: false,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const _StickyHead(),
                _TabsRow(
                  sections: sections,
                  activeIndex: activeIndex,
                  onTapTab: onTapTab,
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
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StickyHead extends StatelessWidget {
  const _StickyHead();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Row(
        children: [
          Icon(PhosphorIconsFill.fire,
              size: 14, color: colors.primary),
          const SizedBox(width: 6),
          Text(
            'Bonne tournée',
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
  final List<FluxSection> sections;
  final int activeIndex;
  final ValueChanged<int> onTapTab;

  const _TabsRow({
    required this.sections,
    required this.activeIndex,
    required this.onTapTab,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 2),
        itemBuilder: (context, i) {
          return _Tab(
            section: sections[i],
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
  final FluxSection section;
  final bool isActive;
  final bool isDone;
  final VoidCallback onTap;

  const _Tab({
    required this.section,
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
        ? section.accent
        : (isDone ? colors.textTertiary : colors.textSecondary);
    // CSS spec: .hf-sticky .tab { padding: 7px 12px 9px; }
    //          .hf-sticky .tab .underline { position: absolute; bottom: 0;
    //            left: 8px; right: 8px; height: 2px; }
    // → the underline is out of flow so it doesn't push the tab taller.
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
                  section.label,
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
                  color: section.accent,
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
