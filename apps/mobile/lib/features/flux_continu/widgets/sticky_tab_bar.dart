import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import '../models/flux_continu_models.dart';

/// Sticky tab bar revealed once the user scrolls past the AppBar threshold.
///
/// Shows one tab per visible section, with the active tab tinted with the
/// section accent. A multi-stop progress fill underlines the bar based on
/// the global scroll progress through the tournée.
class StickyTabBar extends StatelessWidget {
  final List<Section> sections;
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
    final colors = context.facteurColors;
    return Material(
      color: colors.backgroundPrimary,
      elevation: 0,
      child: Container(
        decoration: BoxDecoration(
          color: colors.backgroundPrimary,
          border: Border(
            bottom: BorderSide(color: colors.border, width: 1),
          ),
        ),
        child: SafeArea(
          bottom: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                height: 44,
                child: ListView.builder(
                  scrollDirection: Axis.horizontal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: FacteurSpacing.space3),
                  itemCount: sections.length,
                  itemBuilder: (context, i) {
                    final isActive = i == activeIndex;
                    final isDone = i < activeIndex;
                    return _Tab(
                      section: sections[i],
                      isActive: isActive,
                      isDone: isDone,
                      onTap: () => onTapTab(i),
                    );
                  },
                ),
              ),
              SizedBox(
                height: 4,
                child: CustomPaint(
                  painter: _ProgressPainter(
                    progress: progress.clamp(0.0, 1.0),
                    colors: const [
                      Color(0xFFD35400),
                      Color(0xFFC2185B),
                      Color(0xFF2C3E50),
                      Color(0xFF6C3483),
                    ],
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final Section section;
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
    final color = isActive
        ? section.accent
        : (isDone ? colors.textTertiary : colors.textSecondary);
    final decoration =
        isDone ? TextDecoration.lineThrough : TextDecoration.none;
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.center,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isActive)
                  Container(
                    width: 6,
                    height: 6,
                    margin: const EdgeInsets.only(right: 6),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: section.accent,
                    ),
                  ),
                Text(
                  section.label,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight:
                            isActive ? FontWeight.w700 : FontWeight.w500,
                        decoration: decoration,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Container(
              width: 28,
              height: 2,
              color: isActive ? section.accent : Colors.transparent,
            ),
          ],
        ),
      ),
    );
  }
}

class _ProgressPainter extends CustomPainter {
  final double progress;
  final List<Color> colors;

  _ProgressPainter({required this.progress, required this.colors});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final paint = Paint()
      ..shader = LinearGradient(colors: colors).createShader(rect);
    final clipped = Rect.fromLTWH(0, 0, size.width * progress, size.height);
    canvas.drawRect(clipped, paint);
  }

  @override
  bool shouldRepaint(_ProgressPainter old) =>
      old.progress != progress || old.colors != colors;
}
