import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../config/theme.dart';
import '../../../sources/models/smart_search_result.dart';
import '../../../sources/models/source_model.dart';
import '../../../sources/providers/sources_providers.dart';
import '../../../sources/widgets/source_add_panel.dart';
import '../../../sources/widgets/source_detail_modal.dart';
import '../../../sources/widgets/source_logo_avatar.dart';
import '../../data/source_recommender.dart';
import '../../onboarding_strings.dart';
import '../../providers/onboarding_proof_cache_provider.dart';
import '../../providers/onboarding_provider.dart';
import '../../widgets/add_subscription_card.dart';
import '../../widgets/onboarding_toggle_section.dart';
import '../../widgets/premium_sources_sheet.dart';
import '../../widgets/source_carousel.dart';
import '../../widgets/source_catalog_section.dart';

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

  /// Sources likées au swipe, résolues en [Source] : récapitulées en tête de la
  /// section 1 (puces discrètes « Déjà ajoutés »), exclues des suggestions et
  /// pré-cochées.
  List<Source> _alreadyAdded = const [];

  /// Accordéon piloté : index de la section ouverte (1→4). Une seule à la fois ;
  /// le bouton « Suivant » ouvre la suivante, et sur la dernière il valide.
  int _openSection = 1;

  /// Nombre total de sections de l'accordéon.
  static const int _sectionCount = 4;

  /// Cap des suggestions mises en avant (affichées, cochées ou non).
  static const int _suggestionsLimit = 20;

  /// Parmi les suggestions affichées, seules les `_preselectLimit` premières
  /// (top score) sont pré-cochées ; le reste s'affiche décoché.
  static const int _preselectLimit = 12;

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
    _suggestions = _computeSuggestions(
      reco,
      hasThemes: themes.isNotEmpty,
      excludedIds: swipeLiked.toSet(),
    );
    // Récap « Déjà ajoutés » : sources likées au swipe, dans l'ordre du like.
    final byId = {for (final s in allSources) s.id: s};
    _alreadyAdded = [
      for (final id in swipeLiked)
        if (byId[id] != null) byId[id]!,
    ];
    _preloadSuggestionProfiles(_suggestions!);

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

  /// Jusqu'à `_suggestionsLimit` suggestions : les **spécialistes garantis** en
  /// tête (≥1 par sujet choisi, badge « Spécialisé en X ») pour qu'ils survivent
  /// au cap, puis matched triées score desc + volume-proxy ; sans thèmes (ou sans
  /// match), tri volume-proxy sur tout le pool.
  List<RecommendedSource> _computeSuggestions(
    SourceRecommendation reco, {
    required bool hasThemes,
    Set<String> excludedIds = const {},
  }) {
    final specialists = reco.specialists;
    if (hasThemes && (reco.matched.isNotEmpty || specialists.isNotEmpty)) {
      final sorted = [...reco.matched]
        ..sort((a, b) {
          final byScore = b.score.compareTo(a.score);
          return byScore != 0 ? byScore : _byVolumeProxy(a, b);
        });
      return _dedupById([...specialists, ...sorted])
          .where((r) => !excludedIds.contains(r.source.id))
          .take(_suggestionsLimit)
          .toList();
    }

    final pool = [
      ...reco.matched,
      ...reco.perspective,
      ...reco.gems,
      ...reco.catalog,
    ]..sort(_byVolumeProxy);
    return _dedupById([...specialists, ...pool])
        .where((r) => !excludedIds.contains(r.source.id))
        .take(_suggestionsLimit)
        .toList();
  }

  void _preloadSuggestionProfiles(List<RecommendedSource> suggestions) {
    for (final r in suggestions.take(6)) {
      ref.read(sourceProfileProvider(r.source.id).future).ignore();
    }
  }

  /// Dédoublonne par `source.id` en conservant le premier passage (les
  /// spécialistes garantis, placés en tête, priment).
  static List<RecommendedSource> _dedupById(List<RecommendedSource> list) {
    final seen = <String>{};
    final out = <RecommendedSource>[];
    for (final r in list) {
      if (seen.add(r.source.id)) out.add(r);
    }
    return out;
  }

  /// Catalogue complet (toutes catégories confondues) pour « Voir tout ».
  List<RecommendedSource> _fullCatalog(SourceRecommendation reco) =>
      _dedupById([
        ...reco.specialists,
        ...reco.matched,
        ...reco.perspective,
        ...reco.gems,
        ...reco.catalog,
      ]);

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
        articleOpener: openSourceArticleOnRootNavigator,
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
    ref
        .read(onboardingProofCacheProvider.notifier)
        .update(
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
    final isLastSection = _openSection >= _sectionCount;

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

        // Bouton « Suivant » piloté : tant qu'on n'est pas sur la dernière
        // section, il ouvre la suivante ; sur la dernière il valide la page.
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: FacteurSpacing.space6,
            vertical: FacteurSpacing.space4,
          ),
          child: ElevatedButton(
            onPressed: isLastSection
                ? _continue
                : () => setState(() => _openSection++),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 24),
            ),
            child: Text(
              !isLastSection
                  ? OnboardingStrings.nextButton
                  : (_selectedSourceIds.isEmpty
                      ? OnboardingStrings.skipButton
                      : OnboardingStrings.selectedCount(
                          _selectedSourceIds.length)),
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

  // ── Layout : accordéon piloté (1 section ouverte à la fois) ─────────────

  List<Widget> _buildSourcesLayout(
    BuildContext context,
    SourceRecommendation reco,
    List<Source> allSources,
  ) {
    final colors = context.facteurColors;
    final suggestions = _suggestions ?? const <RecommendedSource>[];
    final selectedSummary =
        OnboardingStrings.finalizeSourcesSummary(_selectedSourceIds.length);

    return [
      Text(
        OnboardingStrings.q9Title,
        style: Theme.of(context).textTheme.displayLarge,
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: FacteurSpacing.space3),
      Text(
        OnboardingStrings.q9Subtitle,
        style: Theme.of(
          context,
        ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: FacteurSpacing.space6),

      // ① Tes suggestions (top pré-cochées)
      OnboardingToggleSection(
        index: 1,
        title: OnboardingStrings.sourcesBlockSuggestionsTitle,
        subtitleWhenCollapsed: selectedSummary,
        description: OnboardingStrings.sourcesBlockSuggestionsDesc,
        expanded: _openSection == 1,
        validated: _openSection > 1,
        onToggle: () => setState(() => _openSection = 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_alreadyAdded.isNotEmpty)
              _AlreadyAddedSources(sources: _alreadyAdded),
            if (suggestions.isEmpty)
              Text(
                OnboardingStrings.q9EmptyList,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: colors.textSecondary),
              )
            else
              SourceCarousel(
                sources: suggestions,
                selectedIds: _selectedSourceIds,
                onToggle: _toggleSource,
                onInfoTap: _showSourceDetail,
              ),
          ],
        ),
      ),
      const SizedBox(height: FacteurSpacing.space4),

      // ② Tes médias habituels → panneau d'ajout
      OnboardingToggleSection(
        index: 2,
        title: OnboardingStrings.sourcesBlockHabitualTitle,
        subtitleWhenCollapsed: OnboardingStrings.sourcesBlockHabitualSubtitle,
        description: OnboardingStrings.sourcesBlockHabitualDesc,
        expanded: _openSection == 2,
        validated: _openSection > 2,
        onToggle: () => setState(() => _openSection = 2),
        child: _buildEmbeddedAddPanel(),
      ),
      const SizedBox(height: FacteurSpacing.space4),

      // ③ Explorer le catalogue (filtrage par thème)
      OnboardingToggleSection(
        index: 3,
        title: OnboardingStrings.sourcesBlockCatalogTitle,
        subtitleWhenCollapsed: OnboardingStrings.sourcesBlockCatalogSubtitle,
        description: OnboardingStrings.sourcesBlockCatalogDesc,
        expanded: _openSection == 3,
        validated: _openSection > 3,
        onToggle: () => setState(() => _openSection = 3),
        child: SourceCatalogSection(
          catalog: _fullCatalog(reco),
          selectedIds: _selectedSourceIds,
          onToggle: _toggleSource,
          onInfoTap: _showSourceDetail,
        ),
      ),
      const SizedBox(height: FacteurSpacing.space4),

      // ④ Tes abonnements presse
      OnboardingToggleSection(
        index: 4,
        title: OnboardingStrings.sourcesBlockSubscriptionsTitle,
        subtitleWhenCollapsed:
            OnboardingStrings.sourcesBlockSubscriptionsSubtitle,
        description: OnboardingStrings.sourcesBlockSubscriptionsDesc,
        expanded: _openSection == 4,
        onToggle: () => setState(() => _openSection = 4),
        child: AddSubscriptionCard(onTap: () => _openPremiumSheet(allSources)),
      ),
    ];
  }

  // ── Briques partagées ────────────────────────────────────────────────────

  Widget _buildEmbeddedAddPanel() {
    return SourceAddPanel(
      padding: EdgeInsets.zero,
      showIntro: false,
      showCommunityGems: false,
      showAddedNudge: false,
      inlineProof: true,
      embedded: true,
      // Autofocus quand la section « médias habituels » est ouverte.
      autoFocusSearch: _openSection == 2,
      onSourceAdded: _onSourceAdded,
    );
  }
}

/// Récap discret des sources déjà ajoutées (likées au swipe), en tête de la
/// section « Tes suggestions » : libellé léger + puces fines (logo ~18px + nom,
/// fond très subtil). Ces sources sont déjà cochées et hors des suggestions.
class _AlreadyAddedSources extends StatelessWidget {
  final List<Source> sources;

  const _AlreadyAddedSources({required this.sources});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: FacteurSpacing.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Déjà ajoutés',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colors.textTertiary,
                ),
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final source in sources)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: colors.textPrimary.withOpacity(0.04),
                    borderRadius: BorderRadius.circular(FacteurRadius.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SourceLogoAvatar(source: source, size: 18, radius: 5),
                      const SizedBox(width: 6),
                      Text(
                        source.name,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: colors.textSecondary,
                            ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
