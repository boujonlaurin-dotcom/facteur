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
import '../../widgets/add_subscription_card.dart';
import '../../widgets/premium_sources_sheet.dart';
import '../../widgets/recommendation_section.dart';
import '../../widgets/source_catalog_section.dart';
import '../../widgets/source_recommendation_card.dart';

/// Q10 : page sources « sur mesure », 4 blocs numérotés (①②③④).
///
/// ① Suggestions sur mesure (jusqu'à 18 affichées, top 9 + sources likées au
/// swipe pré-cochées) ; ② Vos médias habituels (panneau d'ajout replié) ;
/// ③ Explorer le catalogue (replié) ; ④ Vos abonnements presse. (v7 : la
/// question d'intent a été retirée — tout le monde passe par le swipe puis
/// cette page unique.)
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

  /// Panneau d'ajout (« Vous suivez déjà un média ? ») replié derrière un en-tête.
  bool _addPanelExpanded = false;

  /// Cap des suggestions mises en avant (affichées, cochées ou non).
  static const int _suggestionsLimit = 18;

  /// Parmi les suggestions affichées, seules les `_preselectLimit` premières
  /// (top score) sont pré-cochées ; le reste s'affiche décoché.
  static const int _preselectLimit = 9;

  @override
  void initState() {
    super.initState();
    final existingAnswers = ref.read(onboardingProvider).answers;

    // Restore existing selections (back navigation or resume)
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

    final swipeLiked = answers.swipeLiked ?? const <String>[];

    final reco = SourceRecommender.recommend(
      selectedThemes: themes,
      selectedSubtopics: subtopics,
      allSources: allSources,
      objectives: objectives,
      // Axes "profondeur" ré-aiguillés (v6) : déclaratif (approach +
      // indépendance) repondéré par le révélé (swipe).
      depthPref: answers.approach,
      independencePref: answers.independencePref,
      swipeLiked: swipeLiked,
      swipeDisliked: answers.swipeDisliked ?? const <String>[],
    );
    _recommendation = reco;
    _suggestions = _computeSuggestions(reco, hasThemes: themes.isNotEmpty);

    // Pré-sélection : top `_preselectLimit` des suggestions (déjà triées) +
    // toutes les sources swipées à droite (garanties cochées au reveal, même
    // au-delà du rang 9). Le reste des suggestions s'affiche décoché.
    if (!_hasAppliedPreselection) {
      _hasAppliedPreselection = true;
      _selectedSourceIds = {
        ..._suggestions!.take(_preselectLimit).map((r) => r.source.id),
        ...swipeLiked,
      };
    }
  }

  /// Tri à score égal : favorise les gros publieurs mainstream (proxy volume
  /// front, sans champ backend dédié) puis le `followerCount`. Garantit
  /// quelques sources « vivantes » parmi les suggestions.
  static int _byVolumeProxy(RecommendedSource a, RecommendedSource b) {
    final am = a.source.sourceTier == 'mainstream' ? 1 : 0;
    final bm = b.source.sourceTier == 'mainstream' ? 1 : 0;
    if (am != bm) return bm - am; // mainstream d'abord
    return b.source.followerCount.compareTo(a.source.followerCount);
  }

  /// Jusqu'à `_suggestionsLimit` suggestions : matched triées score desc puis
  /// volume-proxy ; sans thèmes (ou sans match), tri volume-proxy sur tout le
  /// pool.
  List<RecommendedSource> _computeSuggestions(
    SourceRecommendation reco, {
    required bool hasThemes,
  }) {
    if (hasThemes && reco.matched.isNotEmpty) {
      final sorted = [...reco.matched]..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : _byVolumeProxy(a, b);
        });
      return sorted.take(_suggestionsLimit).toList();
    }

    final pool = [
      ...reco.matched,
      ...reco.perspective,
      ...reco.gems,
      ...reco.catalog,
    ]..sort(_byVolumeProxy);
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
          ..._buildSourcesLayout(context, reco, allSources),
          const SizedBox(height: FacteurSpacing.space8),
        ],
      ),
    );
  }

  // ── Layout : suggestions d'abord ────────────────────────────────────────

  List<Widget> _buildSourcesLayout(
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

      // ① Suggestions sur mesure (top pré-cochées)
      if (suggestions.isNotEmpty) ...[
        const RecommendationSectionHeader(
          emoji: '①',
          title: OnboardingStrings.sourcesBlockSuggestionsTitle,
          subtitle: OnboardingStrings.q9PreselectionTitle,
        ),
        ...suggestions.map((r) => _buildSuggestionCard(r)),
      ],

      // ② Vos médias habituels → panneau d'ajout replié
      const RecommendationSectionHeader(
        emoji: '②',
        title: OnboardingStrings.sourcesBlockHabitualTitle,
        subtitle: OnboardingStrings.sourcesBlockHabitualSubtitle,
      ),
      _buildAddPanelToggle(context, colors),
      AnimatedSize(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _addPanelExpanded
            ? _buildEmbeddedAddPanel()
            : const SizedBox.shrink(),
      ),

      // ③ Explorer le catalogue (replié)
      const RecommendationSectionHeader(
        emoji: '③',
        title: OnboardingStrings.sourcesBlockCatalogTitle,
        subtitle: OnboardingStrings.sourcesBlockCatalogSubtitle,
      ),
      SourceCatalogSection(
        catalog: _fullCatalog(reco),
        selectedIds: _selectedSourceIds,
        onToggle: _toggleSource,
        onInfoTap: _showSourceDetail,
        initiallyExpanded: false,
      ),

      // ④ Vos abonnements presse
      const RecommendationSectionHeader(
        emoji: '④',
        title: OnboardingStrings.sourcesBlockSubscriptionsTitle,
        subtitle: OnboardingStrings.sourcesBlockSubscriptionsSubtitle,
      ),
      AddSubscriptionCard(onTap: () => _openPremiumSheet(allSources)),
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
      // Autofocus seulement quand l'utilisateur vient de déplier le panneau.
      autoFocusSearch: _addPanelExpanded,
      onSourceAdded: _onSourceAdded,
    );
  }
}
