import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../config/theme.dart';
import '../providers/onboarding_provider.dart';
import '../widgets/onboarding_progress_bar.dart';
import '../widgets/reaction_screen.dart';
import '../onboarding_strings.dart';
import '../../sources/screens/add_source_screen.dart';
import '../../sources/providers/sources_providers.dart';
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
class _SourcesReactionScreen extends ConsumerStatefulWidget {
  final VoidCallback onContinue;

  const _SourcesReactionScreen({
    super.key,
    required this.onContinue,
  });

  @override
  ConsumerState<_SourcesReactionScreen> createState() =>
      _SourcesReactionScreenState();
}

class _SourcesReactionScreenState
    extends ConsumerState<_SourcesReactionScreen> {
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

  void _openPremiumSelection() {
    final colors = context.facteurColors;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _PremiumSourcesSheet(colors: colors),
    );
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
          OutlinedButton.icon(
            onPressed: _openPremiumSelection,
            icon: Icon(
              PhosphorIcons.star(PhosphorIconsStyle.fill),
              size: 18,
            ),
            label: const Text('Indiquer vos abonnements presse'),
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

/// Bottom sheet listing trusted sources with premium toggle switches
class _PremiumSourcesSheet extends ConsumerWidget {
  final FacteurColors colors;

  const _PremiumSourcesSheet({required this.colors});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Vos abonnements presse',
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          Text(
            'Indiquez les sources pour lesquelles vous avez un abonnement payant.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: sourcesAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (err, _) => Center(child: Text('Erreur: $err')),
              data: (sources) {
                final trustedSources = sources
                    .where((s) => s.isTrusted && !s.isMuted)
                    .toList()
                  ..sort((a, b) => a.name.toLowerCase().compareTo(
                      b.name.toLowerCase()));

                if (trustedSources.isEmpty) {
                  return Center(
                    child: Text(
                      'Ajoutez d\'abord des sources de confiance.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            color: colors.textSecondary,
                          ),
                    ),
                  );
                }

                return ListView.separated(
                  shrinkWrap: true,
                  itemCount: trustedSources.length,
                  separatorBuilder: (_, __) => Divider(
                    color: colors.border,
                    height: 1,
                  ),
                  itemBuilder: (context, index) {
                    final source = trustedSources[index];
                    return ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: colors.backgroundSecondary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: source.logoUrl != null
                            ? Image.network(
                                source.logoUrl!,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Icon(
                                  PhosphorIcons.article(),
                                  color: colors.secondary,
                                  size: 18,
                                ),
                              )
                            : Icon(
                                PhosphorIcons.article(),
                                color: colors.secondary,
                                size: 18,
                              ),
                      ),
                      title: Text(
                        source.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: colors.textPrimary,
                            ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: SizedBox(
                        height: 28,
                        child: Switch.adaptive(
                          value: source.hasSubscription,
                          onChanged: (_) {
                            ref
                                .read(userSourcesProvider.notifier)
                                .toggleSubscription(
                                    source.id, source.hasSubscription);
                          },
                          activeTrackColor: colors.primary,
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ),
          SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
        ],
      ),
    );
  }
}
