import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../config/theme.dart';
import '../../../core/auth/auth_state.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_bar.dart';
import '../widgets/reaction_screen.dart';
import '../onboarding_strings.dart';
import 'questions/objective_question.dart';
import 'questions/approach_question.dart';
import 'questions/response_style_question.dart';
import 'questions/gamification_question.dart';
import 'questions/article_count_question.dart';
import 'questions/digest_mode_question.dart';
import 'questions/media_concentration_screen.dart';
import 'questions/themes_question.dart';
import 'questions/subtopics_question.dart';
import 'questions/sources_question.dart';
import 'questions/sources_page2_question.dart';
import 'questions/finalize_question.dart';
import 'questions/sensitive_themes_question.dart';
import 'questions/intro_screen.dart';

/// Écran d'onboarding principal
/// Gère la navigation entre les sections et questions
class OnboardingScreen extends ConsumerStatefulWidget {
  const OnboardingScreen({super.key});

  @override
  ConsumerState<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends ConsumerState<OnboardingScreen> {
  bool _hasShownRestartWelcome = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button and progress bar
            Padding(
              padding: const EdgeInsets.only(
                left: FacteurSpacing.space2,
                right: FacteurSpacing.space6,
                top: FacteurSpacing.space6,
                bottom: 0,
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
                  IconButton(
                    onPressed: () => _showCancelConfirmation(context),
                    icon: const Icon(Icons.close, size: 20),
                    tooltip: 'Quitter le questionnaire',
                  ),
                ],
              ),
            ),

            Text(
              state.currentSection.label,
              style: Theme.of(context).textTheme.labelMedium,
              textAlign: TextAlign.center,
            ),

            const SizedBox(height: FacteurSpacing.space2),

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
          ],
        ),
      ),
    );
  }

  void _showCancelConfirmation(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Annuler les modifications ?'),
        content: const Text(
          'Êtes-vous sûr ? Vos modifications seront perdues.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Continuer'),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(authStateProvider.notifier).setNeedsOnboarding(false);
            },
            child: const Text('Quitter'),
          ),
        ],
      ),
    );
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

      case Section2Question.responseStyle:
        return const ResponseStyleQuestion(key: ValueKey('response_style'));

      case Section2Question.gamification:
        return const GamificationQuestion(key: ValueKey('gamification'));

      case Section2Question.articleCount:
        return const ArticleCountQuestion(key: ValueKey('article_count'));

      case Section2Question.digestMode:
        return const DigestModeQuestion(key: ValueKey('digest_mode'));

      case Section2Question.sensitiveThemes:
        return const SensitiveThemesQuestion(
            key: ValueKey('sensitive_themes'));
    }
  }

  /// Section 3 : Source Preferences (Themes → Sources → Sources Reaction → Finalize)
  Widget _buildSection3Content(OnboardingState state) {
    final question = state.currentSection3Question;

    switch (question) {
      case Section3Question.themes:
        // Show restart welcome screen before themes for returning users
        if (state.isRestart && !_hasShownRestartWelcome) {
          return _RestartWelcomeScreen(
            key: const ValueKey('restart_welcome'),
            onContinue: () => setState(() => _hasShownRestartWelcome = true),
          );
        }
        return const ThemesQuestion(key: ValueKey('themes'));

      case Section3Question.subtopics:
        return const SubtopicsQuestion(key: ValueKey('subtopics'));

      case Section3Question.sources:
        return const SourcesQuestion(key: ValueKey('sources'));

      case Section3Question.sourcesReaction:
        return const SourcesPage2Question(key: ValueKey('sources_page2'));

      case Section3Question.finalize:
        return const FinalizeQuestion(key: ValueKey('finalize'));
    }
  }
}

/// Écran d'accueil pour les users existants qui re-font l'onboarding (v3)
class _RestartWelcomeScreen extends StatelessWidget {
  final VoidCallback onContinue;

  const _RestartWelcomeScreen({
    super.key,
    required this.onContinue,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Spacer(flex: 2),

          Text(
            OnboardingStrings.restartWelcomeTitle,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space3),

          Text(
            OnboardingStrings.restartWelcomeSubtitle,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.textSecondary,
                ),
            textAlign: TextAlign.center,
          ),

          const Spacer(flex: 3),

          ElevatedButton(
            onPressed: onContinue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 24),
            ),
            child: const Text(OnboardingStrings.restartStartButton),
          ),

          const SizedBox(height: FacteurSpacing.space4),
        ],
      ),
    );
  }
}
