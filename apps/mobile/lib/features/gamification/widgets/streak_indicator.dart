import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../../config/theme.dart';
import '../providers/gamification_preference_provider.dart';
import '../providers/streak_animation_provider.dart';
import '../providers/streak_celebration_provider.dart';
import '../../../shared/widgets/completion_stamp.dart' show kStampGreen;
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
  bool _hasStartedDailyAnimation = false;

  /// Célébration « la flamme grossit puis s'incrémente N-1 → N » à la 1re arrivée
  /// sur le feed du jour (depuis la lettre du rituel). Réutilise [_controller]
  /// (le pic du scale, à ~0.55, révèle N et déclenche l'haptique).
  bool _hasStartedCelebration = false;

  /// Pendant la célébration, on affiche d'abord N-1 (valeur figée), puis au pic
  /// on repasse à `null` pour révéler N (= valeur backend courante). `null` en
  /// dehors de la célébration → affichage direct de `currentStreak`.
  int? _displayStreakOverride;

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
    // Au pic du grow (fin du 1er item de la séquence, poids 55 → value 0.55) on
    // bascule N-1 → N + haptique : l'incrément « éclot » au sommet du rebond.
    _controller.addListener(_maybeRevealAtPeak);
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
        final currentStreak = streakAsync.valueOrNull?.currentStreak ?? 0;

        // Célébration prioritaire : « on vient d'ouvrir la lettre » (pending) +
        // gate 1×/jour-tournée pas encore consommé (eligible) + streak actif.
        final pendingCelebration =
            ref.watch(pendingStreakCelebrationProvider);
        final celebrationEligible =
            ref.watch(streakCelebrationEligibleProvider).valueOrNull ?? false;
        final celebrationActive =
            pendingCelebration && celebrationEligible && currentStreak > 0;
        _maybeStartCelebration(celebrationActive, currentStreak);

        // La célébration subsume le simple pulse quotidien → on ne lance pas les
        // deux (sinon double animation de la même flamme).
        final animateToday =
            ref.watch(streakDailyAnimationProvider).valueOrNull ?? false;
        _maybeStartDailyAnimation(
          animateToday && !celebrationActive && !_hasStartedCelebration,
        );

        return streakAsync.when(
          data: (streak) {
            final isActive = streak.currentStreak > 0;
            final dayClosed = streak.dailyGoalReached;
            final textColor = isActive
                ? colors.primary
                : colors.textSecondary.withValues(alpha: 0.55);
            final displayStreak = _displayStreakOverride ?? streak.currentStreak;

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
                        alpha: isActive ? 0.03 : 0.015,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      // Journée refermée : un anneau vert fin, en **additif**.
                      // Jamais de flamme désaturée tant que l'objectif n'est
                      // pas atteint — ce serait un signal de déficit affiché
                      // tous les matins. On n'enlève rien, on ajoute parfois.
                      border: Border.all(
                        color: dayClosed
                            ? kStampGreen.withValues(alpha: 0.55)
                            : colors.primary.withValues(alpha: 0.06),
                        width: dayClosed ? 1.5 : 1,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 29,
                          height: 29,
                          child: AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: _scale.value,
                                child: SvgPicture.asset(
                                  'assets/icons/streak_flame.svg',
                                  width: 29,
                                  height: 29,
                                  colorFilter: isActive
                                      ? null
                                      : ColorFilter.mode(
                                          colors.textSecondary
                                              .withValues(alpha: 0.45),
                                          BlendMode.srcIn,
                                        ),
                                ),
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        // « Roll » N-1 → N : le chiffre glisse vers le haut à
                        // l'incrément (AnimatedSwitcher keyé sur la valeur).
                        AnimatedSwitcher(
                          duration: FacteurDurations.fast,
                          transitionBuilder: (child, animation) {
                            final slide = Tween<Offset>(
                              begin: const Offset(0, 0.6),
                              end: Offset.zero,
                            ).animate(animation);
                            return ClipRect(
                              child: SlideTransition(
                                position: slide,
                                child: FadeTransition(
                                  opacity: animation,
                                  child: child,
                                ),
                              ),
                            );
                          },
                          child: Text(
                            '$displayStreak',
                            key: ValueKey<int>(displayStreak),
                            style: textTheme.labelMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: textColor,
                            ),
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
              width: 29,
              height: 29,
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

  /// Démarre la célébration « grow + incrément N-1 → N » (une seule fois). Pose
  /// l'affichage à N-1, consomme les deux gates (célébration + pulse quotidien
  /// qu'elle subsume) et efface le flag pending, puis lance le grow. Le pic du
  /// scale ([_maybeRevealAtPeak]) révélera N + haptique. Reduce-motion : affiche
  /// directement N sans animation, gate marqué.
  void _maybeStartCelebration(bool celebrationActive, int currentStreak) {
    if (!celebrationActive || _hasStartedCelebration) return;
    _hasStartedCelebration = true;
    // La célébration subsume le pulse quotidien : on marque aussi son garde
    // interne pour qu'il ne se déclenche jamais en doublon.
    _hasStartedDailyAnimation = true;

    final reduceMotion = MediaQuery.of(context).disableAnimations;

    // Appelé pendant le build : on pose l'override **synchronement** (pas de
    // setState) pour que la 1re frame peinte affiche déjà N-1 — sinon la valeur
    // réelle N apparaîtrait fugacement avant le « roll » N-1 → N. Cosmétique pur
    // (le backend a déjà incrémenté au read → currentStreak == N) ; on ne
    // persiste aucune « valeur célébrée », le gate 1×/jour-tournée suffit.
    if (!reduceMotion) {
      _displayStreakOverride = (currentStreak - 1).clamp(0, currentStreak);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await ref.read(streakCelebrationGateProvider).markCelebratedForToday();
      await ref.read(streakDailyAnimationGateProvider).markAnimatedForToday();
      if (!mounted) return;
      ref.read(pendingStreakCelebrationProvider.notifier).state = false;

      // reduce-motion : affichage direct de N (aucune animation), gates consommés.
      if (reduceMotion) return;
      await _controller.forward(from: 0);
    });
  }

  void _maybeRevealAtPeak() {
    if (_displayStreakOverride == null) return;
    if (_controller.value >= 0.55) {
      HapticFeedback.mediumImpact();
      setState(() => _displayStreakOverride = null);
    }
  }
}
