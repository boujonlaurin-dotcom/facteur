import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../../config/topic_labels.dart';
import '../../../sources/models/source_model.dart';
import '../../../sources/providers/sources_providers.dart';
import '../../../sources/screens/add_source_screen.dart';
import '../../../sources/widgets/source_detail_modal.dart';
import '../../data/source_recommender.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/premium_sources_sheet.dart';
import '../../widgets/recommendation_section.dart';
import '../../widgets/source_recommendation_card.dart';

/// Sources Page 2 — "Allez plus loin."
///
/// Shows CTAs for adding custom sources and premium subscriptions,
/// plus the full catalogue grouped by theme.
class SourcesPage2Question extends ConsumerStatefulWidget {
  const SourcesPage2Question({super.key});

  @override
  ConsumerState<SourcesPage2Question> createState() =>
      _SourcesPage2QuestionState();
}

class _SourcesPage2QuestionState extends ConsumerState<SourcesPage2Question> {
  late Set<String> _selectedSourceIds;
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  SourceRecommendation? _recommendation;

  @override
  void initState() {
    super.initState();
    // Restore selections from Page 1
    final existingSources =
        ref.read(onboardingProvider).answers.preferredSources;
    _selectedSourceIds =
        existingSources != null ? existingSources.toSet() : {};

    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text;
      });
    });
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
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
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

  Future<void> _openAddSource() async {
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const AddSourceScreen()),
    );
  }

  void _openPremiumSheet(List<Source> allSources) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PremiumSourcesSheet(
        allSources: allSources,
        onDone: (subscribedIds) {
          // Mark subscriptions via the sources provider
          final sourcesNotifier = ref.read(userSourcesProvider.notifier);
          for (final source in allSources.where((s) => s.isCurated)) {
            final wasSubscribed = source.hasSubscription;
            final isNowSubscribed = subscribedIds.contains(source.id);
            if (wasSubscribed != isNowSubscribed) {
              sourcesNotifier.toggleSubscription(source.id, wasSubscribed);
            }
          }
        },
      ),
    );
  }

  void _continue() {
    ref
        .read(onboardingProvider.notifier)
        .continueFromSourcesPage2(_selectedSourceIds.toList());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final sourcesAsync = ref.watch(userSourcesProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
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

              return _buildContent(context, reco, sources);
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

  Widget _buildContent(
    BuildContext context,
    SourceRecommendation reco,
    List<Source> allSources,
  ) {
    final colors = context.facteurColors;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: FacteurSpacing.space6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FacteurSpacing.space6),

          // Title
          Text(
            OnboardingStrings.sourcesPage2Title,
            style: Theme.of(context).textTheme.displayLarge,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Text(
            OnboardingStrings.sourcesPage2Subtitle,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),

          const SizedBox(height: FacteurSpacing.space6),

          // CTA: Add any source
          OutlinedButton.icon(
            onPressed: _openAddSource,
            icon: Icon(
              PhosphorIcons.plus(PhosphorIconsStyle.bold),
              size: 20,
            ),
            label: const Text(OnboardingStrings.addAnySourceButton),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              side: BorderSide(color: colors.primary, width: 1.5),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              foregroundColor: colors.primary,
            ),
          ),

          const SizedBox(height: FacteurSpacing.space3),

          // CTA: Premium subscriptions
          OutlinedButton.icon(
            onPressed: () => _openPremiumSheet(allSources),
            icon: Icon(
              PhosphorIcons.star(PhosphorIconsStyle.bold),
              size: 20,
            ),
            label: const Text(OnboardingStrings.premiumSubscriptionsButton),
            style: OutlinedButton.styleFrom(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: 16,
              ),
              side: BorderSide(
                color: colors.primary.withValues(alpha: 0.5),
                width: 1.5,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              foregroundColor: colors.primary,
            ),
          ),

          // Catalogue section
          if (reco.catalog.isNotEmpty) ...[
            const RecommendationSectionHeader(
              emoji: '📚',
              title: 'Tout le catalogue',
              subtitle: 'Toutes les sources disponibles, classées par thème',
            ),

            // Search bar
            Padding(
              padding: const EdgeInsets.only(bottom: FacteurSpacing.space3),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: OnboardingStrings.q9SearchHint,
                  prefixIcon:
                      Icon(Icons.search, color: colors.textSecondary),
                  filled: true,
                  fillColor: colors.surface,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: FacteurSpacing.space4,
                    vertical: FacteurSpacing.space3,
                  ),
                  border: OutlineInputBorder(
                    borderRadius:
                        BorderRadius.circular(FacteurRadius.full),
                    borderSide: BorderSide.none,
                  ),
                  hintStyle: TextStyle(color: colors.textSecondary),
                ),
                style: TextStyle(color: colors.textPrimary),
                onTapOutside: (_) => FocusScope.of(context).unfocus(),
              ),
            ),

            // Catalogue grouped by theme
            ..._buildCatalogueByTheme(context, reco.catalog),

            if (_searchQuery.isNotEmpty &&
                _filteredCatalog(reco.catalog).isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                    vertical: FacteurSpacing.space4),
                child: Text(
                  OnboardingStrings.q9NoMatch,
                  style: TextStyle(color: colors.textSecondary),
                  textAlign: TextAlign.center,
                ),
              ),
          ],

          const SizedBox(height: FacteurSpacing.space8),
        ],
      ),
    );
  }

  /// Builds the catalogue grouped by theme with mini-headers.
  List<Widget> _buildCatalogueByTheme(
    BuildContext context,
    List<RecommendedSource> catalog,
  ) {
    final colors = context.facteurColors;
    final filtered = _filteredCatalog(catalog);

    // Group by theme slug
    final grouped = <String, List<RecommendedSource>>{};
    for (final r in filtered) {
      final theme = r.source.theme ?? 'other';
      grouped.putIfAbsent(theme, () => []).add(r);
    }

    // Sort groups by macroThemeOrder
    final sortedThemes = grouped.keys.toList()
      ..sort((a, b) {
        final macroA = getTopicMacroTheme(a);
        final macroB = getTopicMacroTheme(b);
        final idxA = macroA != null ? macroThemeOrder.indexOf(macroA) : 999;
        final idxB = macroB != null ? macroThemeOrder.indexOf(macroB) : 999;
        return idxA.compareTo(idxB);
      });

    final widgets = <Widget>[];
    for (final themeSlug in sortedThemes) {
      final sources = grouped[themeSlug]!;
      final macroTheme = getTopicMacroTheme(themeSlug);
      final label = macroTheme ?? getTopicLabel(themeSlug);
      final emoji =
          macroTheme != null ? getMacroThemeEmoji(macroTheme) : '';

      // Mini-header for the theme group
      widgets.add(Padding(
        padding: const EdgeInsets.only(
          top: FacteurSpacing.space4,
          bottom: FacteurSpacing.space2,
        ),
        child: Text(
          '$emoji $label (${sources.length})',
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
        ),
      ));

      // Source cards for this group
      for (final r in sources) {
        widgets.add(Padding(
          padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
          child: SourceRecommendationCard(
            recommendation: r,
            isSelected: _selectedSourceIds.contains(r.source.id),
            onToggle: () => _toggleSource(r.source.id),
            onInfoTap: () => _showSourceDetail(r.source),
            showReason: false,
          ),
        ));
      }
    }

    return widgets;
  }

  List<RecommendedSource> _filteredCatalog(List<RecommendedSource> catalog) {
    if (_searchQuery.isEmpty) return catalog;
    final query = _searchQuery.toLowerCase();
    return catalog
        .where((r) => r.source.name.toLowerCase().contains(query))
        .toList();
  }
}
