import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../gamification/providers/streak_provider.dart';

/// Absolute-positioned app bar for the Flux Continu V1.8 screen.
///
/// Layout: streak fire pill (left) · Facteur wordmark (center) · settings
/// icon (right, 30×30). Sits at top: 32 over the scroll content, swapped
/// with the sticky tab bar once the user scrolls past the threshold.
class FluxAppBar extends ConsumerWidget {
  const FluxAppBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.facteurColors;
    final streakAsync = ref.watch(streakProvider);
    final streak = streakAsync.valueOrNull?.currentStreak ?? 0;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          FacteurSpacing.space4,
          FacteurSpacing.space2,
          FacteurSpacing.space4,
          0,
        ),
        child: Row(
          children: [
            _StreakPill(streak: streak, accent: colors.primary),
            const Spacer(),
            Text(
              'Facteur',
              style: GoogleFonts.fraunces(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: 0.2,
              ),
            ),
            const Spacer(),
            _SettingsButton(
              onTap: () => context.push(RoutePaths.settings),
              colors: colors,
            ),
          ],
        ),
      ),
    );
  }
}

class _StreakPill extends StatelessWidget {
  final int streak;
  final Color accent;

  const _StreakPill({required this.streak, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(FacteurRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.local_fire_department_rounded, color: accent, size: 16),
          const SizedBox(width: 4),
          Text(
            '$streak',
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _SettingsButton extends StatelessWidget {
  final VoidCallback onTap;
  final FacteurColors colors;

  const _SettingsButton({required this.onTap, required this.colors});

  @override
  Widget build(BuildContext context) {
    return InkResponse(
      onTap: onTap,
      radius: 22,
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          border: Border.all(color: colors.border, width: 1),
        ),
        child: Icon(
          Icons.tune_rounded,
          color: colors.textSecondary,
          size: 16,
        ),
      ),
    );
  }
}
