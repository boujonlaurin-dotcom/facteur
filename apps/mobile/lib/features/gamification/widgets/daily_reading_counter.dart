import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/streak_provider.dart';

/// Minimalist daily reading counter displayed in the feed header.
///
/// Shows "X lu" (X read) for today's consumption count.
/// Animates subtly when the count increases.
class DailyReadingCounter extends ConsumerStatefulWidget {
  const DailyReadingCounter({super.key});

  @override
  ConsumerState<DailyReadingCounter> createState() =>
      _DailyReadingCounterState();
}

class _DailyReadingCounterState extends ConsumerState<DailyReadingCounter>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  int? _previousCount;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 400),
      vsync: this,
    );

    _scaleAnimation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.2,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 40,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.2,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.elasticOut)),
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
        // Use weeklyCount as a proxy for daily count for now
        // (Backend enhancement needed for true daily count)
        final dailyCount = streak.weeklyCount;

        // Trigger animation if count changed
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _animateIfChanged(dailyCount);
        });

        return AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return Transform.scale(
              scale: _scaleAnimation.value,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    PhosphorIcons.newspaper(PhosphorIconsStyle.regular),
                    size: 14,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '$dailyCount lu${dailyCount > 1 ? 's' : ''}',
                    style: textTheme.labelMedium?.copyWith(
                      color: colors.textSecondary,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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
