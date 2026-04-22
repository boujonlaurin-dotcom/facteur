import 'dart:async';

import 'package:flutter/material.dart';

import '../../../config/theme.dart';
import 'serein_toggle_chip.dart';

/// Sticky header for the digest screen: title + Serein chip + compact
/// progress dots. The "X/Y" counter fades in transiently after each
/// increment (feedback that an article has been counted), then fades out.
class DigestStickyHeader extends StatefulWidget {
  final int processedCount;
  final int dailyGoal;

  const DigestStickyHeader({
    super.key,
    required this.processedCount,
    required this.dailyGoal,
  });

  @override
  State<DigestStickyHeader> createState() => _DigestStickyHeaderState();
}

class _DigestStickyHeaderState extends State<DigestStickyHeader> {
  Timer? _timer;
  bool _showCounterText = false;

  @override
  void didUpdateWidget(covariant DigestStickyHeader old) {
    super.didUpdateWidget(old);
    if (widget.processedCount > old.processedCount &&
        widget.dailyGoal > 0) {
      setState(() => _showCounterText = true);
      _timer?.cancel();
      _timer = Timer(const Duration(milliseconds: 2500), () {
        if (mounted) setState(() => _showCounterText = false);
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final goal = widget.dailyGoal;
    final processed = widget.processedCount;
    final isComplete = goal > 0 && processed >= goal;
    final showText = _showCounterText || isComplete;

    return Container(
      color: colors.backgroundPrimary,
      padding: const EdgeInsets.only(
        left: FacteurSpacing.space4 + 2, // 18 → aligns with card horizontal 4+14
        right: FacteurSpacing.space4 + 2,
        top: FacteurSpacing.space3,
        bottom: FacteurSpacing.space2,
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Text(
                  "L'Essentiel du jour",
                  style: Theme.of(context).textTheme.displaySmall?.copyWith(
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.3,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              const SereinToggleChip(),
            ],
          ),
          if (goal > 0)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  _buildCompactCounter(colors, processed, goal, isComplete),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 260),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) => FadeTransition(
                      opacity: animation,
                      child: SizeTransition(
                        axis: Axis.horizontal,
                        axisAlignment: -1,
                        sizeFactor: animation,
                        child: child,
                      ),
                    ),
                    child: showText
                        ? Padding(
                            key: const ValueKey('counter-text'),
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '$processed/$goal',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.2,
                                color: isComplete
                                    ? colors.success
                                    : colors.primary,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(
                            key: ValueKey('counter-empty'),
                          ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildCompactCounter(
    FacteurColors colors,
    int processed,
    int denominator,
    bool isComplete,
  ) {
    final color = isComplete ? colors.success : colors.primary;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(denominator, (i) {
        final isDone = i < processed;
        return Container(
          width: 8,
          height: 2,
          margin: EdgeInsets.only(right: i < denominator - 1 ? 2 : 0),
          decoration: BoxDecoration(
            color: isDone
                ? color
                : colors.textTertiary.withOpacity(0.25),
            borderRadius: BorderRadius.circular(1.25),
          ),
        );
      }),
    );
  }
}

/// Pinned delegate wrapping the sticky header. Height is fixed to ensure
/// the transient "X/Y" text never overflows during its size animation.
class DigestStickyHeaderDelegate extends SliverPersistentHeaderDelegate {
  final int processedCount;
  final int dailyGoal;

  const DigestStickyHeaderDelegate({
    required this.processedCount,
    required this.dailyGoal,
  });

  static const double _extent = 72;

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return DigestStickyHeader(
      processedCount: processedCount,
      dailyGoal: dailyGoal,
    );
  }

  @override
  bool shouldRebuild(covariant DigestStickyHeaderDelegate old) {
    return processedCount != old.processedCount ||
        dailyGoal != old.dailyGoal;
  }
}
