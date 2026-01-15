import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../providers/streak_provider.dart';

/// Widget displaying daily progress toward the user's consumption goal.
///
/// Shows "X/Y" format (e.g., "3/10") where X is articles read today
/// and Y is the daily goal. Animates with scale AND font size increase when count changes.
class DailyProgressIndicator extends ConsumerStatefulWidget {
  const DailyProgressIndicator({super.key});

  @override
  ConsumerState<DailyProgressIndicator> createState() =>
      _DailyProgressIndicatorState();
}

class _DailyProgressIndicatorState extends ConsumerState<DailyProgressIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _fontSizeMultiplier;
  int? _previousCount;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );

    // Scale animation (bounce effect)
    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.3)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.3, end: 1.0)
            .chain(CurveTween(curve: Curves.elasticOut)),
        weight: 60,
      ),
    ]).animate(_controller);

    // Font size multiplier (grows then returns)
    _fontSizeMultiplier = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.0, end: 1.4)
            .chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(begin: 1.4, end: 1.0)
            .chain(CurveTween(curve: Curves.easeInOut)),
        weight: 60,
      ),
    ]).animate(_controller);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _animateIfChanged(int currentCount) {
    if (_previousCount != null && currentCount > _previousCount!) {
      // Animate when count increases
      _controller.forward(from: 0.0);
    }
    _previousCount = currentCount;
  }

  @override
  Widget build(BuildContext context) {
    final streakAsync = ref.watch(streakProvider);
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return streakAsync.when(
      data: (streak) {
        // Trigger animation if count changed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _animateIfChanged(streak.weeklyCount);
        });

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.backgroundSecondary,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: colors.primary.withValues(alpha: 0.1),
                    width: 1,
                  ),
                ),
                child: Text(
                  '${streak.weeklyCount} / ${streak.weeklyGoal} lus',
                  style: textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                    fontSize: (textTheme.labelMedium?.fontSize ?? 12) *
                        _fontSizeMultiplier.value,
                  ),
                ),
              ),
            );
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }
}
