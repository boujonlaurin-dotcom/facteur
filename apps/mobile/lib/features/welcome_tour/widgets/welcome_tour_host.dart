import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tutorial_coach_mark/tutorial_coach_mark.dart';

import '../../../config/routes.dart';
import '../../../core/auth/auth_state.dart';
import '../controllers/welcome_tour_controller.dart';
import 'tour_bubble.dart';

/// Clés globales des 3 tabs de la bottom nav — partagées entre
/// `ShellScaffold` (attache) et `WelcomeTourHost` (cible le coachmark).
///
/// Déclarées au niveau module pour que les deux widgets utilisent la MÊME
/// instance de clé (sinon le coachmark ne trouve pas sa cible).
final GlobalKey bottomNavDigestKey =
    GlobalKey(debugLabel: 'bottomNavDigestKey');
final GlobalKey bottomNavFeedKey = GlobalKey(debugLabel: 'bottomNavFeedKey');
final GlobalKey bottomNavSettingsKey =
    GlobalKey(debugLabel: 'bottomNavSettingsKey');

class _StepMeta {
  const _StepMeta({
    required this.path,
    required this.key,
    required this.stamp,
    required this.title,
    required this.body,
  });

  final String path;
  final GlobalKey key;
  final String stamp;
  final String title;
  final String body;
}

final List<_StepMeta> _steps = [
  _StepMeta(
    path: RoutePaths.digest,
    key: bottomNavDigestKey,
    stamp: '1/3',
    title: "L'Essentiel",
    body:
        'Chaque matin, Facteur te présente les 5 infos les plus traitées en France pour sortir de ta bulle et te permettre de comparer les points de vues.',
  ),
  _StepMeta(
    path: RoutePaths.feed,
    key: bottomNavFeedKey,
    stamp: '2/3',
    title: 'Ton Flux',
    body:
        'Tous les articles de tes sources de confiance, filtrés en fonction de tes préférences. Personnalise le contenu chaque jour en balayant les cartes qui t\'intéressent moins.',
  ),
  _StepMeta(
    path: RoutePaths.settings,
    key: bottomNavSettingsKey,
    stamp: '3/3',
    title: 'Paramètres & Personnalisation',
    body:
        'Ajuste régulièrement tes préférences de thèmes, de sources, et les préférences de ton mode serein ici.',
  ),
];

/// Widget monté dans le `ShellScaffold`. Écoute l'état d'auth + le controller
/// du tour, navigue entre `/digest`, `/feed`, `/settings` au fil des étapes
/// et pose un coachmark ciblé sur le tab correspondant.
///
/// Render : `SizedBox.shrink()` (pas de contenu visible — tout passe par
/// `TutorialCoachMark.show(context:)` qui monte son propre overlay).
class WelcomeTourHost extends ConsumerStatefulWidget {
  const WelcomeTourHost({super.key});

  @override
  ConsumerState<WelcomeTourHost> createState() => _WelcomeTourHostState();
}

class _WelcomeTourHostState extends ConsumerState<WelcomeTourHost> {
  TutorialCoachMark? _current;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final tourState = ref.read(welcomeTourControllerProvider);
      // If the controller is already active (e.g. the shell was remounted
      // after an onboarding redirect), re-render the coachmark on the
      // current step instead of starting from scratch.
      if (tourState.active) {
        _showStep(tourState.currentStep);
        return;
      }
      _maybeStartFromAuth(ref.read(authStateProvider));
    });
  }

  @override
  void dispose() {
    _current?.finish();
    _current = null;
    super.dispose();
  }

  void _maybeStartFromAuth(AuthState auth) {
    if (!auth.isAuthenticated) return;
    if (!auth.isEmailConfirmed) return;
    if (auth.needsOnboarding) return;
    if (auth.welcomeTourSeen) return;
    if (ref.read(welcomeTourControllerProvider).active) return;
    ref.read(welcomeTourControllerProvider.notifier).start();
  }

  Future<void> _handleTourChange(
      WelcomeTourState? prev, WelcomeTourState next) async {
    if (!next.active) {
      _dismissCurrent();
      return;
    }
    final stepChanged = prev?.currentStep != next.currentStep;
    final becameActive = prev?.active != true;
    if (!stepChanged && !becameActive) return;
    await _showStep(next.currentStep);
  }

  Future<void> _showStep(int step) async {
    _dismissCurrent();
    if (step < 0 || step >= _steps.length) return;
    final meta = _steps[step];

    final currentLocation =
        GoRouter.of(context).routerDelegate.currentConfiguration.uri.path;
    if (currentLocation != meta.path) {
      context.go(meta.path);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 180));
      if (!mounted) return;
      final tourState = ref.read(welcomeTourControllerProvider);
      if (!tourState.active || tourState.currentStep != step) return;
      if (meta.key.currentContext == null) return;

      final target = TargetFocus(
        identify: 'welcome-tour-step-$step',
        keyTarget: meta.key,
        shape: ShapeLightFocus.RRect,
        radius: 14,
        enableOverlayTab: false,
        enableTargetTab: false,
        contents: [
          TargetContent(
            align: ContentAlign.top,
            padding: const EdgeInsets.only(bottom: 12),
            builder: (_, __) => TourBubble(
              stamp: meta.stamp,
              title: meta.title,
              body: meta.body,
              isLast: step == _steps.length - 1,
              onSkip: () =>
                  ref.read(welcomeTourControllerProvider.notifier).skip(),
              onNext: () =>
                  ref.read(welcomeTourControllerProvider.notifier).next(),
            ),
          ),
        ],
      );

      _current = TutorialCoachMark(
        targets: [target],
        colorShadow: const Color(0xFF2C2A29),
        opacityShadow: 0.7,
        paddingFocus: 8,
        hideSkip: true,
        focusAnimationDuration: const Duration(milliseconds: 250),
        pulseAnimationDuration: const Duration(milliseconds: 400),
      )..show(context: context);
    });
  }

  Future<void> _handleFinishSignal(WelcomeTourFinishSignal signal) async {
    if (signal == WelcomeTourFinishSignal.none) return;
    _dismissCurrent();
    await ref.read(authStateProvider.notifier).markWelcomeTourSeen();
    if (!mounted) return;
    final path = signal == WelcomeTourFinishSignal.firstDigest
        ? '${RoutePaths.digest}?first=true'
        : RoutePaths.digest;
    context.go(path);
    ref.read(welcomeTourFinishSignalProvider.notifier).state =
        WelcomeTourFinishSignal.none;
  }

  void _dismissCurrent() {
    _current?.finish();
    _current = null;
  }

  @override
  Widget build(BuildContext context) {
    ref.listen<AuthState>(authStateProvider, (prev, next) {
      _maybeStartFromAuth(next);
    });
    ref.listen<WelcomeTourState>(welcomeTourControllerProvider,
        (prev, next) => _handleTourChange(prev, next));
    ref.listen<WelcomeTourFinishSignal>(
      welcomeTourFinishSignalProvider,
      (prev, next) => _handleFinishSignal(next),
    );
    return const SizedBox.shrink();
  }
}
