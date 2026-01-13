import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/theme.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_bar.dart';
import '../widgets/reaction_screen.dart';
import 'questions/objective_question.dart';
import 'questions/age_question.dart';
import 'questions/gender_question.dart';
import 'questions/approach_question.dart';
import 'questions/perspective_question.dart';
import 'questions/response_style_question.dart';
import 'questions/content_recency_question.dart';
import 'questions/gamification_question.dart';
import 'questions/weekly_goal_question.dart';
import 'questions/themes_question.dart';
import 'questions/format_question.dart';
import 'questions/source_comparison_question.dart';
import 'questions/personal_goal_question.dart';
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
  @override
  Widget build(BuildContext context) {
    final state = ref.watch(onboardingProvider);

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            // Barre de progression
            Padding(
              padding: const EdgeInsets.all(FacteurSpacing.space6),
              child: OnboardingProgressBar(
                progress: state.progress,
                section: state.currentSection,
              ),
            ),

            // Contenu de la question
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                transitionBuilder: (child, animation) {
                  return FadeTransition(
                    opacity: animation,
                    child: SlideTransition(
                      position:
                          Tween<Offset>(
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

  /// Section 1 : Overview (Q1-Q4 + R1)
  Widget _buildSection1Content(OnboardingState state) {
    final question = state.currentSection1Question;

    switch (question) {
      case Section1Question.intro:
        return const IntroScreen(key: ValueKey('intro'));

      case Section1Question.objective:
        return const ObjectiveQuestion(key: ValueKey('objective'));

      case Section1Question.objectiveReaction:
        final objective = state.answers.objective ?? 'learn';
        final reaction = ObjectiveReactionMessages.messages[objective]!;
        return ReactionScreen(
          key: const ValueKey('objective_reaction'),
          title: reaction.title,
          message: reaction.message,
          onContinue: () {
            ref.read(onboardingProvider.notifier).continueAfterReaction();
          },
        );

      case Section1Question.ageRange:
        return const AgeQuestion(key: ValueKey('age'));

      case Section1Question.gender:
        return const GenderQuestion(key: ValueKey('gender'));

      case Section1Question.approach:
        return const ApproachQuestion(key: ValueKey('approach'));
    }
  }

  /// Section 2 : App Preferences (Q5-Q8b + R2)
  Widget _buildSection2Content(OnboardingState state) {
    final question = state.currentSection2Question;

    switch (question) {
      case Section2Question.perspective:
        return const PerspectiveQuestion(key: ValueKey('perspective'));

      case Section2Question.responseStyle:
        return const ResponseStyleQuestion(key: ValueKey('response_style'));

      case Section2Question.contentRecency:
        return const ContentRecencyQuestion(key: ValueKey('content_recency'));

      case Section2Question.preferencesReaction:
        final reaction = PreferencesReactionMessages.getReaction(
          perspective: state.answers.perspective,
          responseStyle: state.answers.responseStyle,
          contentRecency: state.answers.contentRecency,
          objective: state.answers.objective,
          themes: state.answers.themes,
        );
        return ReactionScreen(
          key: const ValueKey('preferences_reaction'),
          title: reaction.title,
          message: reaction.message,
          onContinue: () {
            ref
                .read(onboardingProvider.notifier)
                .continueAfterSection2Reaction();
          },
        );

      case Section2Question.gamification:
        return const GamificationQuestion(key: ValueKey('gamification'));

      case Section2Question.weeklyGoal:
        return const WeeklyGoalQuestion(key: ValueKey('weekly_goal'));
    }
  }

  /// Section 3 : Source Preferences (Q9-Q11 + Finalize)
  Widget _buildSection3Content(OnboardingState state) {
    final question = state.currentSection3Question;

    switch (question) {
      case Section3Question.themes:
        return const ThemesQuestion(key: ValueKey('themes'));

      case Section3Question.formatPreference:
        return const FormatQuestion(key: ValueKey('format'));

      case Section3Question.sourceComparison1:
        return const SourceComparisonQuestion(
          key: ValueKey('source_comparison'),
        );

      case Section3Question.personalGoal:
        return const PersonalGoalQuestion(key: ValueKey('personal_goal'));

      case Section3Question.finalize:
        return const FinalizeQuestion(key: ValueKey('finalize'));
    }
  }
}
