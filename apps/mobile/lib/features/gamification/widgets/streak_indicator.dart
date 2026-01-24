import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/streak_provider.dart';

class StreakIndicator extends ConsumerWidget {
  const StreakIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final streakAsync = ref.watch(streakProvider);
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;

    return streakAsync.when(
      data: (streak) {
        // if (streak.currentStreak == 0) return const SizedBox.shrink();

        final isActive = streak.currentStreak > 0;
        final flameColor = isActive
            ? Colors.orange
            : colors.textSecondary.withValues(alpha: 0.3);
        final textColor = isActive
            ? colors.textPrimary
            : colors.textSecondary.withValues(alpha: 0.5);

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: colors.backgroundSecondary
                .withValues(alpha: isActive ? 1 : 0.5),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive
                  ? colors.primary.withValues(alpha: 0.1)
                  : Colors.transparent,
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                PhosphorIcons.fire(PhosphorIconsStyle.fill),
                color: flameColor,
                size: 16,
              ),
              const SizedBox(width: 4),
              Text(
                '${streak.currentStreak}',
                style: textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: textColor,
                ),
              ),
            ],
          ),
        );
      },
      loading: () => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Icon(PhosphorIcons.fire(PhosphorIconsStyle.regular),
            size: 16, color: colors.textSecondary.withValues(alpha: 0.3)),
      ),
      error: (e, s) {
        // Debugging: print error
        debugPrint('Streak Error: $e');
        return const SizedBox.shrink();
      },
    );
  }
}
