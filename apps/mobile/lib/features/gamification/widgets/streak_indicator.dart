import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/gamification_preference_provider.dart';
import '../providers/streak_animation_provider.dart';
import '../providers/streak_provider.dart';
import 'streak_explainer_modal.dart';

class StreakIndicator extends ConsumerStatefulWidget {
  const StreakIndicator({super.key});

  @override
  ConsumerState<StreakIndicator> createState() => _StreakIndicatorState();
}

class _StreakIndicatorState extends ConsumerState<StreakIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _glow;
  bool _hasStartedDailyAnimation = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.0,
          end: 1.22,
        ).chain(CurveTween(curve: Curves.easeOutBack)),
        weight: 55,
      ),
      TweenSequenceItem(
        tween: Tween<double>(
          begin: 1.22,
          end: 1.0,
        ).chain(CurveTween(curve: Curves.easeOut)),
        weight: 45,
      ),
    ]).animate(_controller);
    _glow = Tween<double>(
      begin: 0.0,
      end: 0.30,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final textTheme = Theme.of(context).textTheme;
    final gamificationAsync = ref.watch(gamificationPreferenceProvider);

    return gamificationAsync.when(
      data: (enabled) {
        if (!enabled) return const SizedBox.shrink();

        final streakAsync = ref.watch(streakProvider);
        final animateToday =
            ref.watch(streakDailyAnimationProvider).valueOrNull ?? false;
        _maybeStartDailyAnimation(animateToday);

        return streakAsync.when(
          data: (streak) {
            final isActive = streak.currentStreak > 0;
            final flameColor = colors.primary.withValues(
              alpha: isActive ? 0.78 : 0.38,
            );
            final textColor = isActive
                ? colors.textPrimary
                : colors.textSecondary.withValues(alpha: 0.55);

            return Semantics(
              button: true,
              label:
                  'Serie actuelle : ${streak.currentStreak} jours. Ouvrir le detail.',
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => StreakExplainerModal.show(context),
                  child: Container(
                    constraints: const BoxConstraints(minHeight: 36),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: colors.primary.withValues(
                        alpha: isActive ? 0.04 : 0.02,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        color: colors.primary.withValues(alpha: 0.10),
                        width: 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 16,
                          height: 16,
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              return DecoratedBox(
                                decoration: BoxDecoration(
                                  boxShadow: [
                                    BoxShadow(
                                      color: colors.primary.withValues(
                                        alpha: _glow.value,
                                      ),
                                      blurRadius: 12,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Transform.scale(
                                  scale: _scale.value,
                                  child: SvgPicture.asset(
                                    'assets/icons/streak_flame.svg',
                                    width: 16,
                                    height: 16,
                                    colorFilter: isActive
                                        ? null
                                        : ColorFilter.mode(
                                            colors.textSecondary
                                                .withValues(alpha: 0.45),
                                            BlendMode.srcIn,
                                          ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${streak.currentStreak}',
                          style: textTheme.labelMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                            color: textColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
          loading: () => Container(
            constraints: const BoxConstraints(minHeight: 36, minWidth: 36),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: SvgPicture.asset(
              'assets/icons/streak_flame.svg',
              width: 16,
              height: 16,
              colorFilter: ColorFilter.mode(
                colors.primary.withValues(alpha: 0.3),
                BlendMode.srcIn,
              ),
            ),
          ),
          error: (e, s) {
            debugPrint('Streak Error: $e');
            return const SizedBox.shrink();
          },
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (e, s) {
        debugPrint('Gamification Preference Error: $e');
        return const SizedBox.shrink();
      },
    );
  }

  void _maybeStartDailyAnimation(bool shouldAnimate) {
    if (!shouldAnimate || _hasStartedDailyAnimation) return;
    _hasStartedDailyAnimation = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(streakDailyAnimationGateProvider).markAnimatedForToday();
      if (!mounted) return;
      await _controller.forward(from: 0);
    });
  }
}
