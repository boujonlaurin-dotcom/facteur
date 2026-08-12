import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/analytics_provider.dart';
import '../providers/onboarding_analytics.dart';
import '../providers/onboarding_provider.dart';
import '../services/onboarding_push_priming.dart';
import '../widgets/onboarding_notif_priming.dart';
import '../widgets/onboarding_progress_bar.dart';
import '../widgets/reaction_screen.dart';
import '../onboarding_strings.dart';
import 'questions/objective_question.dart';
import 'questions/approach_question.dart';
import 'questions/independence_question.dart';
import 'questions/media_concentration_screen.dart';
import 'questions/themes_question.dart';
import 'questions/subtopics_question.dart';
import 'questions/sources_question.dart';
import 'questions/swipe_disambiguator_question.dart';
import 'questions/finalize_question.dart';
import 'questions/intro_screen.dart';

/// Écran d'onboarding principal
/// Gère la navigation entre les sections et questions
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  /// Instrumentation du funnel (story 31.1). Vit ici plutôt que dans le
  /// provider : celui-ci est aussi lu hors onboarding.
  late final OnboardingStepTracker _stepTracker;

  /// Amorce notif précoce (étape 3/4) : planifiée une seule fois, quelques
  /// secondes après avoir atteint l'étape, pour capter tôt la permission.
  Timer? _primingTimer;
  bool _primingScheduled = false;

  @override
  void initState() {
    super.initState();
    _stepTracker = OnboardingStepTracker(ref.read(analyticsServiceProvider));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final state = ref.read(onboardingProvider);
      _stepTracker.onState(state);
      unawaited(_maybeSchedulePriming(state));
    });
  }

  @override
  void dispose() {
    _primingTimer?.cancel();
    super.dispose();
  }

  /// Arme (une seule fois) l'écran d'amorce ~4 s après avoir atteint l'étape
  /// `objective` (ou au-delà), pour une session anonyme qui ne l'a pas encore
  /// vu. `objective` est un écran de « dwell » : le délai atterrit de façon
  /// fiable pendant que l'utilisateur est présent. Le seuil est ancré sur
  /// l'index de l'enum (pas un littéral) pour survivre à un réordonnancement
  /// des questions.
  ///
  /// `_primingScheduled` passe à `true` de façon synchrone avant le premier
  /// `await` : la garde de ré-entrance tient donc même si `ref.listen` rappelle
  /// pendant l'ouverture de la box Hive.
  Future<void> _maybeSchedulePriming(OnboardingState state) async {
    if (_primingScheduled) return;
    if (state.globalQuestionIndex < Section1Question.objective.index) return;
    if (!ref.read(authStateProvider).isAnonymous) return;
    _primingScheduled = true;
    if (await ref.read(onboardingPushPrimingProvider).hasSeenPriming()) return;
    _primingTimer = Timer(const Duration(seconds: 4), () {
      if (!mounted) return;
      final current = ref.read(onboardingProvider);
      // Ne pas tirer pendant la transition de conclusion (finalize).
      if (current.isReadyToFinalize) return;
      unawaited(
        showOnboardingNotifPriming(
          context,
          ref,
          step: current.globalQuestionIndex,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);
    ref.listen<OnboardingState>(
      onboardingProvider,
      (_, next) {
        _stepTracker.onState(next);
        unawaited(_maybeSchedulePriming(next));
      },
    );

    return Scaffold(
      // Le clavier recouvre le bas sans redimensionner le body ; l'espace
      // scrollable est réservé par le padding viewInsets des SingleChildScrollView.
      resizeToAvoidBottomInset: false,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button and progress bar
            Padding(
              padding: const EdgeInsets.only(
                left: FacteurSpacing.space2,
                right: FacteurSpacing.space6,
                top: FacteurSpacing.space6,
                bottom: FacteurSpacing.space4,
              ),
              child: Row(
                children: [
                  if (state.currentQuestionIndex > 0 ||
                      state.currentSection != OnboardingSection.overview)
                    IconButton(
                      onPressed: () {
                        ref.read(onboardingProvider.notifier).goBack();
                      },
                      icon: const Icon(Icons.arrow_back_ios_new, size: 20),
                      tooltip: OnboardingStrings.backButtonTooltip,
                    )
                  else
                    const SizedBox(width: 48),
                  Expanded(
                    child: OnboardingProgressBar(
                      sectionProgress: state.sectionProgress,
                      section: state.currentSection,
                    ),
                  ),
                  // Story 31.1 — pas de sortie pour une session anonyme : elle
                  // n'a ni compte ni profil, quitter le questionnaire la
                  // laisserait sur un feed vide sans jamais reproposer la
                  // création de compte. La croix reste pour un utilisateur
                  // authentifié qui refait son onboarding.
                  if (ref.watch(authStateProvider).isAnonymous)
                    const SizedBox(width: 48)
                  else
                    IconButton(
                      onPressed: () => _showCancelConfirmation(context),
                      icon: const Icon(Icons.close, size: 20),
                      tooltip: 'Quitter le questionnaire',
                    ),
                ],
              ),
            ),

            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position: Tween<Offset>(
                        begin: const Offset(0.05, 0),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: animation,
                          curve: Curves.easeOut,
                        ),
                      ),
                      child: child,
                    ),
                  );
                },
                child: _buildCurrentContent(state),
              ),
            ),

            // Bouton « Passer » : un seul point d'insertion, conditionnel à la
            // question courante (cf. OnboardingState.isSkippable). Applique un
            // défaut sain et avance — évite de toucher chaque écran de question.
            if (state.isSkippable)
              Padding(
                padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                child: TextButton(
                  onPressed: () {
                    ref.read(onboardingProvider.notifier).skipCurrentQuestion();
                  },
                  child: Text(OnboardingStrings.skipButton),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _showCancelConfirmation(BuildContext context) async {
    final quit = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler les modifications ?'),
        content: const Text(
          'Êtes-vous sûr ? Vos modifications seront perdues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
    if (!mounted || quit != true) return;
    // `showDialog` ne complète qu'une fois le dialog entièrement démonté
    // (animation de fermeture comprise), pas une frame après le `pop`.
    // `setNeedsOnboarding` notifie alors le `refreshListenable` de GoRouter, qui
    // recalcule `redirect` et remplace la route onboarding — sans courir contre
    // un Navigator racine encore en train de fermer le dialog.
    await ref.read(authStateProvider.notifier).setNeedsOnboarding(false);
  }

  Widget _buildCurrentContent(OnboardingState state) {
    switch (state.currentSection) {
      case OnboardingSection.overview:
        return _buildSection1Content(state);
      case OnboardingSection.appPreferences:
        return _buildSection2Content(state);
      case OnboardingSection.sourcePreferences:
        return _buildSection3Content(state);
    }
  }

  /// Section 1 : Overview
  Widget _buildSection1Content(OnboardingState state) {
    final question = state.currentSection1Question;

    switch (question) {
      case Section1Question.intro1:
        return const WelcomeScreen(key: ValueKey('intro1'));

      case Section1Question.intro2:
        return const IntroScreen2(key: ValueKey('intro2'));

      case Section1Question.mediaConcentration:
        return const MediaConcentrationScreen(
            key: ValueKey('media_concentration'));

      case Section1Question.objective:
        return const ObjectiveQuestion(key: ValueKey('objective'));

      case Section1Question.objectiveReaction:
        final objectives = state.answers.objectives ?? ['noise'];
        final reaction = ObjectiveReactionMessages.getReaction(objectives);
        return ReactionScreen(
          key: const ValueKey('objective_reaction'),
          title: reaction.title,
          message: reaction.message,
          onContinue: () {
            ref.read(onboardingProvider.notifier).continueAfterReaction();
          },
        );
    }
  }

  /// Section 2 : App Preferences
  Widget _buildSection2Content(OnboardingState state) {
    final question = state.currentSection2Question;

    switch (question) {
      case Section2Question.approach:
        return const ApproachQuestion(key: ValueKey('approach'));

      case Section2Question.independence:
        return const IndependenceQuestion(key: ValueKey('independence'));
    }
  }

  /// Section 3 : Source Preferences
  /// (Themes → Subtopics → Swipe → Sources → Finalize)
  Widget _buildSection3Content(OnboardingState state) {
    final question = state.currentSection3Question;

    switch (question) {
      case Section3Question.themes:
        return const ThemesQuestion(key: ValueKey('themes'));

      case Section3Question.subtopics:
        return const SubtopicsQuestion(key: ValueKey('subtopics'));

      case Section3Question.swipe:
        return const SwipeDisambiguatorQuestion(key: ValueKey('swipe'));

      case Section3Question.sources:
        return const SourcesQuestion(key: ValueKey('sources'));

      case Section3Question.finalize:
        return const FinalizeQuestion(key: ValueKey('finalize'));
    }
  }
}

