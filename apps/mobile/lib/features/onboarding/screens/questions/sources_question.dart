import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/source_model.dart';
import '../../../sources/providers/sources_providers.dart';
import '../../../sources/widgets/source_detail_modal.dart';
import '../../data/source_recommender.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/recommendation_section.dart';
import '../../widgets/source_recommendation_card.dart';

/// Q9 : Sources recommandées personnalisées — Page 1.
///
/// Affiche 3 sections: Pour vous, Élargis ta vision, Pépites.
/// Le catalogue et les CTAs sont sur la Page 2 (sourcesReaction).
class SourcesQuestion extends ConsumerStatefulWidget {
  const SourcesQuestion({super.key});

  @override
  ConsumerState<SourcesQuestion> createState() => _SourcesQuestionState();
}

class _SourcesQuestionState extends ConsumerState<SourcesQuestion> {
  Set<String> _selectedSourceIds = {};
  bool _hasAppliedPreselection = false;
  SourceRecommendation? _recommendation;
  bool _showAllMatched = false;

  /// Max matched sources visible before "Voir plus"
  static const int _matchedVisibleLimit = 8;

  @override
  void initState() {
    super.initState();
    // Restore existing selections (back navigation or resume)
    final existingAnswers = ref.read(onboardingProvider).answers;
    final existingSources = existingAnswers.preferredSources;
    if (existingSources != null && existingSources.isNotEmpty) {
      _selectedSourceIds = existingSources.toSet();
      _hasAppliedPreselection = true;
    }
  }

  void _computeRecommendations(List<Source> allSources) {
    if (_recommendation != null) return;

    final answers = ref.read(onboardingProvider).answers;
    final themes = answers.themes ?? [];
    final subtopics = answers.subtopics ?? [];
    final objectives = answers.objectives ?? [];

    _recommendation = SourceRecommender.recommend(
      selectedThemes: themes,
      selectedSubtopics: subtopics,
      allSources: allSources,
      objectives: objectives,
    );

    // Apply preselection (matched + gems)
    if (!_hasAppliedPreselection) {
      _hasAppliedPreselection = true;
      _selectedSourceIds = _recommendation!.preselectedIds;
    }
  }

  void _toggleSource(String sourceId) {
    HapticFeedback.lightImpact();
    setState(() {
      if (_selectedSourceIds.contains(sourceId)) {
        _selectedSourceIds.remove(sourceId);
      } else {
        _selectedSourceIds.add(sourceId);
      }
    });
  }

  void _showSourceDetail(Source source) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => SourceDetailModal(
        source: source,
        onToggleTrust: () => _toggleSource(source.id),
      ),
    );
  }

  void _continue() {
    ref
        .read(onboardingProvider.notifier)
        .selectSources(_selectedSourceIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Content
        Expanded(
          child: sourcesAsync.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (err, _) => Center(
              child: Text(
                OnboardingStrings.q9LoadingError,
                style: TextStyle(color: colors.textSecondary),
              ),
            ),
            data: (sources) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (_recommendation == null) {
                  setState(() => _computeRecommendations(sources));
                }
              });

              final reco = _recommendation;
              if (reco == null) {
                return const Center(child: CircularProgressIndicator());
              }

              return _buildContent(context, reco);
            },
          ),
        ),

        // Continue button
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space6,
            vertical: FacteurSpacing.space4,
          ),
          child: ElevatedButton(
            onPressed: _continue,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
            child: Text(
              _selectedSourceIds.isEmpty
                  ? OnboardingStrings.skipButton
                  : OnboardingStrings.selectedCount(
                      _selectedSourceIds.length),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContent(BuildContext context, SourceRecommendation reco) {
    final colors = context.facteurColors;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FacteurSpacing.space6),

          // Title
          Text(
            OnboardingStrings.q9Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Text(
            OnboardingStrings.q9Subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          // Section: Pour vous
          if (reco.matched.isNotEmpty) ...[
            const RecommendationSectionHeader(
              emoji: '🎯',
              title: 'Pour vous',
              subtitle: 'Pré-sélectionnées pour vous',
            ),
            ..._visibleMatched(reco.matched).map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                  child: SourceRecommendationCard(
                    recommendation: r,
                    isSelected: _selectedSourceIds.contains(r.source.id),
                    onToggle: () => _toggleSource(r.source.id),
                    onInfoTap: () => _showSourceDetail(r.source),
                  ),
                )),
            // "Voir plus" button
            if (!_showAllMatched &&
                reco.matched.length > _matchedVisibleLimit)
              Padding(
                padding: const EdgeInsets.only(
                  top: FacteurSpacing.space2,
                  bottom: FacteurSpacing.space2,
                ),
                child: TextButton(
                  onPressed: () => setState(() => _showAllMatched = true),
                  child: Text(
                    'Voir ${reco.matched.length - _matchedVisibleLimit} de plus',
                    style: TextStyle(color: colors.primary),
                  ),
                ),
              ),
          ],

          // Section: Élargissez votre vision
          if (reco.perspective.isNotEmpty) ...[
            const RecommendationSectionHeader(
              emoji: '🔭',
              title: 'Élargissez votre vision',
              subtitle:
                  'Des sources qui challengent vos habitudes de lecture.',
            ),
            ...reco.perspective.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                  child: SourceRecommendationCard(
                    recommendation: r,
                    isSelected: _selectedSourceIds.contains(r.source.id),
                    onToggle: () => _toggleSource(r.source.id),
                    onInfoTap: () => _showSourceDetail(r.source),
                  ),
                )),
          ],

          // Section: Pépites
          if (reco.gems.isNotEmpty) ...[
            const RecommendationSectionHeader(
              emoji: '💎',
              title: 'Pépites',
              subtitle:
                  'Des sources rares qui pourraient changer votre vision du monde.',
            ),
            ...reco.gems.map((r) => Padding(
                  padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
                  child: SourceRecommendationCard(
                    recommendation: r,
                    isSelected: _selectedSourceIds.contains(r.source.id),
                    onToggle: () => _toggleSource(r.source.id),
                    onInfoTap: () => _showSourceDetail(r.source),
                  ),
                )),
          ],

          const SizedBox(height: FacteurSpacing.space8),
        ],
      ),
    );
  }

  /// Returns visible matched sources, respecting the collapse limit.
  List<RecommendedSource> _visibleMatched(List<RecommendedSource> matched) {
    if (_showAllMatched || matched.length <= _matchedVisibleLimit) {
      return matched;
    }
    return matched.take(_matchedVisibleLimit).toList();
  }
}
