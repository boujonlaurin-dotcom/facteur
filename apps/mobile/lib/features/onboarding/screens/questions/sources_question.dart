import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/smart_search_result.dart';
import '../../../sources/models/source_model.dart';
import '../../../sources/providers/sources_providers.dart';
import '../../../sources/widgets/source_add_panel.dart';
import '../../../sources/widgets/source_detail_modal.dart';
import '../../data/source_recommender.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_proof_cache_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/premium_sources_sheet.dart';
import '../../widgets/recommendation_section.dart';
import '../../widgets/source_catalog_section.dart';
import '../../widgets/source_recommendation_card.dart';

/// Q10 : page sources adaptative (remplace les ex-pages 1 + 2).
///
/// Deux variantes selon la réponse à « Avec quels médias préférez-vous
/// partir ? » (Q9c) :
/// - `curious` (défaut) : suggestions en avant (max 7, pré-cochées),
///   recherche de ses médias repliée dessous ;
/// - `knows` : recherche smart-search proéminente (avec preuve « Connecté »
///   à l'ajout), suggestions repliées dessous.
/// Dans les deux cas : catalogue complet replié + CTA abonnements presse.
class SourcesQuestion extends ConsumerStatefulWidget {
  const SourcesQuestion({super.key});

  @override
  ConsumerState<SourcesQuestion> createState() => _SourcesQuestionState();
}

class _SourcesQuestionState extends ConsumerState<SourcesQuestion> {
  Set<String> _selectedSourceIds = {};
  bool _hasAppliedPreselection = false;
  SourceRecommendation? _recommendation;
  List<RecommendedSource>? _suggestions;

  /// Variante figée à l'entrée de la page (changement via retour sur Q9c).
  late final String _intent;

  bool get _isCurious => _intent != 'knows';

  /// Variante knows : suggestions repliées à 5, « Voir plus » → 7.
  bool _showAllSuggestions = false;

  /// Variante curious : panneau d'ajout replié derrière un en-tête.
  bool _addPanelExpanded = false;

  /// Cap des suggestions mises en avant (et pré-cochées en curious).
  static const int _suggestionsLimit = 7;

  /// Suggestions visibles en variante knows avant « Voir plus ».
  static const int _knowsVisibleLimit = 5;

  @override
  void initState() {
    super.initState();
    final existingAnswers = ref.read(onboardingProvider).answers;
    _intent = existingAnswers.sourcesIntent ?? 'curious';

    // Restore existing selections (back navigation or resume)
    final existingSources = existingAnswers.preferredSources;
    if (existingSources != null && existingSources.isNotEmpty) {
      _selectedSourceIds = existingSources.toSet();
      _hasAppliedPreselection = true;
    }
    // La variante knows ne pré-coche rien : l'utilisateur part de ses médias.
    if (!_isCurious) {
      _hasAppliedPreselection = true;
    }
  }

  void _computeRecommendations(List<Source> allSources) {
    if (_recommendation != null) return;

    final answers = ref.read(onboardingProvider).answers;
    final themes = answers.themes ?? [];
    final subtopics = answers.subtopics ?? [];
    final objectives = answers.objectives ?? [];

    final reco = SourceRecommender.recommend(
      selectedThemes: themes,
      selectedSubtopics: subtopics,
      allSources: allSources,
      objectives: objectives,
    );
    _recommendation = reco;
    _suggestions = _computeSuggestions(reco, hasThemes: themes.isNotEmpty);

    // Pré-sélection (curious uniquement) : limitée aux suggestions visibles,
    // au lieu des 13-20 matched+gems d'avant.
    if (!_hasAppliedPreselection) {
      _hasAppliedPreselection = true;
      _selectedSourceIds = _suggestions!.map((r) => r.source.id).toSet();
    }
  }

  /// Max 7 suggestions : matched triées score desc puis followers desc ;
  /// sans thèmes (ou sans match), tri pur par followers sur tout le curé.
  List<RecommendedSource> _computeSuggestions(
    SourceRecommendation reco, {
    required bool hasThemes,
  }) {
    int byFollowers(RecommendedSource a, RecommendedSource b) =>
        b.source.followerCount.compareTo(a.source.followerCount);

    if (hasThemes && reco.matched.isNotEmpty) {
      final sorted = [...reco.matched]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : byFollowers(a, b);
        });
      return sorted.take(_suggestionsLimit).toList();
    }

    final pool = [
      ...reco.matched,
      ...reco.perspective,
      ...reco.gems,
      ...reco.catalog,
    ]..sort(byFollowers);
    return pool.take(_suggestionsLimit).toList();
  }

  /// Catalogue complet (toutes catégories confondues) pour « Voir tout ».
  List<RecommendedSource> _fullCatalog(SourceRecommendation reco) => [
        ...reco.matched,
        ...reco.perspective,
        ...reco.gems,
        ...reco.catalog,
      ];

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
        isSelectedOverride: _selectedSourceIds.contains(source.id),
      ),
    );
  }

  void _openPremiumSheet(List<Source> allSources) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => PremiumSourcesSheet(
        allSources: allSources,
        selectedSourceIds: _selectedSourceIds,
      ),
    );
  }

  /// Ajout via le panneau smart-search : sélectionne la source et capture la
  /// preuve (derniers articles) pour l'animation de conclusion.
  void _onSourceAdded(SmartSearchResult result) {
    final sourceId = result.sourceId;
    if (sourceId == null || sourceId.isEmpty || sourceId == 'null') return;

    setState(() => _selectedSourceIds.add(sourceId));
    ref.read(onboardingProofCacheProvider.notifier).update(
          (cache) => {
            ...cache,
            sourceId: SourceProofSeed(
              sourceId: sourceId,
              name: result.name,
              logoUrl: result.faviconUrl,
              items: result.recentItems,
            ),
          },
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
                if (_recommendation == null && mounted) {
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
              padding: const EdgeInsets.symmetric(vertical: 24),
            ),
            child: Text(
              _selectedSourceIds.isEmpty
                  ? OnboardingStrings.skipButton
                  : OnboardingStrings.selectedCount(_selectedSourceIds.length),
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
    return SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        FacteurSpacing.space6,
        0,
        FacteurSpacing.space6,
        MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SizedBox(height: FacteurSpacing.space6),
          if (_isCurious)
            ..._buildCuriousLayout(context, reco, allSources)
          else
            ..._buildKnowsLayout(context, reco, allSources),
          const SizedBox(height: FacteurSpacing.space8),
        ],
      ),
    );
  }

  // ── Variante curious : suggestions d'abord ──────────────────────────────

  List<Widget> _buildCuriousLayout(
    BuildContext context,
    SourceRecommendation reco,
    List<Source> allSources,
  ) {
    final colors = context.facteurColors;
    final suggestions = _suggestions ?? const <RecommendedSource>[];

    return [
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

      // Suggestions (pré-cochées)
      if (suggestions.isNotEmpty) ...[
        const RecommendationSectionHeader(
          emoji: '🎯',
          title: OnboardingStrings.sourcesSuggestionsTitle,
          subtitle: OnboardingStrings.q9PreselectionTitle,
        ),
        ...suggestions.map((r) => _buildSuggestionCard(r)),
      ],

      // « Vous suivez déjà un média ? » → panneau d'ajout replié
      const SizedBox(height: FacteurSpacing.space4),
      _buildAddPanelToggle(context, colors),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _addPanelExpanded
            ? _buildEmbeddedAddPanel()
            : const SizedBox.shrink(),
      ),

      // Catalogue complet replié + abonnements presse
      const SizedBox(height: FacteurSpacing.space4),
      SourceCatalogSection(
        catalog: _fullCatalog(reco),
        selectedIds: _selectedSourceIds,
        onToggle: _toggleSource,
        onInfoTap: _showSourceDetail,
        initiallyExpanded: suggestions.isEmpty,
      ),
      const SizedBox(height: FacteurSpacing.space4),
      _buildPremiumCta(colors, allSources),
    ];
  }

  // ── Variante knows : recherche d'abord ──────────────────────────────────

  List<Widget> _buildKnowsLayout(
    BuildContext context,
    SourceRecommendation reco,
    List<Source> allSources,
  ) {
    final colors = context.facteurColors;
    final suggestions = _suggestions ?? const <RecommendedSource>[];
    final visibleSuggestions = _showAllSuggestions
        ? suggestions
        : suggestions.take(_knowsVisibleLimit).toList();

    return [
      Text(
        OnboardingStrings.sourcesKnowsTitle,
        style: Theme.of(context).textTheme.displayLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: FacteurSpacing.space3),
      Text(
        'Recherchez vos médias, on les connecte à votre tournée.',
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: colors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: FacteurSpacing.space2),

      // Panneau d'ajout proéminent (preuve « Connecté » à l'ajout)
      _buildEmbeddedAddPanel(),

      // « Ou laissez-vous guider » : mêmes suggestions, repliées
      if (suggestions.isNotEmpty) ...[
        const SizedBox(height: FacteurSpacing.space4),
        const RecommendationSectionHeader(
          emoji: '🎯',
          title: OnboardingStrings.sourcesGuideMeTitle,
          subtitle: OnboardingStrings.q9PreselectionTitle,
        ),
        ...visibleSuggestions.map((r) => _buildSuggestionCard(r)),
        if (!_showAllSuggestions && suggestions.length > _knowsVisibleLimit)
          Padding(
            padding: const EdgeInsets.symmetric(
              vertical: FacteurSpacing.space2,
            ),
            child: TextButton(
              onPressed: () => setState(() => _showAllSuggestions = true),
              child: Text(
                OnboardingStrings.sourcesSeeMore,
                style: TextStyle(color: colors.primary),
              ),
            ),
          ),
      ],

      // Catalogue complet replié + abonnements presse
      const SizedBox(height: FacteurSpacing.space4),
      SourceCatalogSection(
        catalog: _fullCatalog(reco),
        selectedIds: _selectedSourceIds,
        onToggle: _toggleSource,
        onInfoTap: _showSourceDetail,
      ),
      const SizedBox(height: FacteurSpacing.space4),
      _buildPremiumCta(colors, allSources),
    ];
  }

  // ── Briques partagées ────────────────────────────────────────────────────

  Widget _buildSuggestionCard(RecommendedSource r) {
    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space2),
      child: SourceRecommendationCard(
        recommendation: r,
        isSelected: _selectedSourceIds.contains(r.source.id),
        onToggle: () => _toggleSource(r.source.id),
        onInfoTap: () => _showSourceDetail(r.source),
      ),
    );
  }

  /// En-tête repliable « Vous suivez déjà un média ? » (variante curious).
  Widget _buildAddPanelToggle(BuildContext context, FacteurColors colors) {
    return Semantics(
      button: true,
      expanded: _addPanelExpanded,
      label: OnboardingStrings.sourcesAlreadyFollowTitle,
      child: InkWell(
        onTap: () => setState(() => _addPanelExpanded = !_addPanelExpanded),
        borderRadius: BorderRadius.circular(FacteurRadius.medium),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space2,
            vertical: FacteurSpacing.space3,
          ),
          child: Row(
            children: [
              Icon(
                PhosphorIcons.magnifyingGlass(),
                size: 20,
                color: colors.textSecondary,
              ),
              const SizedBox(width: FacteurSpacing.space2),
              Expanded(
                child: Text(
                  OnboardingStrings.sourcesAlreadyFollowTitle,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              AnimatedRotation(
                turns: _addPanelExpanded ? 0.5 : 0,
                duration: const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: Icon(
                  PhosphorIcons.caretDown(),
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmbeddedAddPanel() {
    return SourceAddPanel(
      padding: EdgeInsets.zero,
      showIntro: false,
      showCommunityGems: false,
      showAddedNudge: false,
      inlineProof: true,
      embedded: true,
      // Autofocus seulement quand l'utilisateur vient de déplier (curious) :
      // en knows le panneau est visible dès l'entrée, le clavier attendra.
      autoFocusSearch: _isCurious && _addPanelExpanded,
      onSourceAdded: _onSourceAdded,
    );
  }

  Widget _buildPremiumCta(FacteurColors colors, List<Source> allSources) {
    return OutlinedButton.icon(
      onPressed: () => _openPremiumSheet(allSources),
      icon: Icon(
        PhosphorIcons.star(PhosphorIconsStyle.bold),
        size: 20,
      ),
      label: const Text(OnboardingStrings.premiumSubscriptionsButton),
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        side: BorderSide(color: colors.primary.withValues(alpha: 0.5),
            width: 1.5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        foregroundColor: colors.primary,
      ),
    );
  }
}
