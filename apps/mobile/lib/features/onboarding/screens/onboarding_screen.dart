import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_bar.dart';
import '../widgets/reaction_screen.dart';
import '../onboarding_strings.dart';
import '../../sources/screens/add_source_screen.dart';
import 'questions/objective_question.dart';
import 'questions/age_question.dart';
import 'questions/approach_question.dart';
import 'questions/perspective_question.dart';
import 'questions/response_style_question.dart';
import 'questions/gamification_question.dart';
import 'questions/article_count_question.dart';
import 'questions/digest_mode_question.dart';
import 'questions/media_concentration_screen.dart';
import 'questions/themes_question.dart';
import 'questions/sources_question.dart';
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
                  if (state.currentQuestionIndex > 0)
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
                      progress: state.progress,
                      section: state.currentSection,
                    ),
                  ),
                  const SizedBox(width: 48),
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

      case Section1Question.ageRange:
        return const AgeQuestion(key: ValueKey('age'));

      case Section1Question.approach:
        return const ApproachQuestion(key: ValueKey('approach'));
    }
  }

  /// Section 2 : App Preferences
  Widget _buildSection2Content(OnboardingState state) {
    final question = state.currentSection2Question;

    switch (question) {
      case Section2Question.perspective:
        return const PerspectiveQuestion(key: ValueKey('perspective'));

      case Section2Question.responseStyle:
        return const ResponseStyleQuestion(key: ValueKey('response_style'));

      case Section2Question.gamification:
        return const GamificationQuestion(key: ValueKey('gamification'));

      case Section2Question.articleCount:
        return const ArticleCountQuestion(key: ValueKey('article_count'));

      case Section2Question.digestMode:
        return const DigestModeQuestion(key: ValueKey('digest_mode'));
    }
  }

  /// Section 3 : Source Preferences (Themes → Sources → Sources Reaction → Finalize)
  Widget _buildSection3Content(OnboardingState state) {
    final question = state.currentSection3Question;

    switch (question) {
      case Section3Question.themes:
        return const ThemesQuestion(key: ValueKey('themes'));

      case Section3Question.sources:
        return const SourcesQuestion(key: ValueKey('sources'));

      case Section3Question.sourcesReaction:
        return _SourcesReactionScreen(
          key: const ValueKey('sources_reaction'),
          onContinue: () {
            ref
                .read(onboardingProvider.notifier)
                .continueAfterSourcesReaction();
          },
        );

      case Section3Question.finalize:
        return const FinalizeQuestion(key: ValueKey('finalize'));
    }
  }
}

/// Widget dédié pour l'écran sources reaction avec compteur de sources ajoutées
class _SourcesReactionScreen extends StatefulWidget {
  final VoidCallback onContinue;

  const _SourcesReactionScreen({
    super.key,
    required this.onContinue,
  });

  @override
  State<_SourcesReactionScreen> createState() => _SourcesReactionScreenState();
}

class _SourcesReactionScreenState extends State<_SourcesReactionScreen> {
  int _addedCount = 0;
  static const _recommendedCount = 3;

  Future<void> _openAddSource() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => const AddSourceScreen(),
      ),
    );
    // L'utilisateur revient de AddSourceScreen — incrémenter le compteur
    if (mounted) {
      setState(() => _addedCount++);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;

    return ReactionScreen(
      title: OnboardingStrings.sourcesReactionTitle,
      message: OnboardingStrings.sourcesReactionMessage,
      onContinue: widget.onContinue,
      extraAction: Column(
        children: [
          OutlinedButton.icon(
            onPressed: _openAddSource,
            icon: Icon(
              PhosphorIcons.plus(PhosphorIconsStyle.bold),
              size: 18,
            ),
            label: const Text(OnboardingStrings.addSourceButton),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 14,
              ),
              side: BorderSide(
                color: colors.primary.withValues(alpha: 0.3),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Text(
            _addedCount >= _recommendedCount
                ? '$_addedCount source${_addedCount > 1 ? 's' : ''} ajoutée${_addedCount > 1 ? 's' : ''}'
                : '$_addedCount/$_recommendedCount sources (minimum recommandé)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: _addedCount >= _recommendedCount
                      ? colors.success
                      : colors.textTertiary,
                ),
          ),
        ],
      ),
    );
  }
}
