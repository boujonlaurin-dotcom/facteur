import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../digest/models/digest_models.dart';
import '../../digest/models/dual_digest_response.dart';
import '../../digest/providers/digest_provider.dart'
    show digestRepositoryProvider;
import '../../digest/providers/serein_toggle_provider.dart';
import '../../digest/repositories/digest_repository.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart' show feedRepositoryProvider;
import '../../feed/providers/tab_order_prefs_provider.dart'
    show tabOrderPrefsProvider;
import '../../feed/repositories/feed_repository.dart';
import '../../grille/providers/grille_provider.dart';
import '../../my_interests/models/user_interests_state.dart';
import '../../my_interests/models/user_sources_state.dart';
import '../../my_interests/providers/user_interests_provider.dart';
import '../../my_interests/providers/user_sources_state_provider.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/providers/sources_providers.dart'
    show userSourcesProvider;
import '../../veille/providers/veille_active_config_provider.dart';
import '../models/flux_continu_models.dart';
import '../repositories/essentiel_repository.dart';
import '../repositories/flux_continu_repository.dart';
import '../services/flux_continu_cache_service.dart';
import '../services/tournee_progress_service.dart';
import '../utils/notif_teasers.dart';
import '../utils/theme_color_mapping.dart';
import 'tournee_order_prefs_provider.dart'; // tourneeOrderPrefsProvider, TourneeOrderState, applyOrder (réexporté)

/// Accent applied to the legacy "Actus du jour" digest topic section
/// (DigestTopicSection avec kind=essentiel). Distinct de l'accent
/// `colors.sectionEssentiel` exposé via le thème car ce dernier dépend du
/// BuildContext. Aligné avec `EssentielSection.accent` (carte hi-fi).
const Color _kEssentielAccent = Color(0xFFB0470A);

/// Accent applied to the Bonnes Nouvelles section banner.
const Color _kBonnesAccent = Color(0xFF2E7D32);

/// Accent applied to the Veille section banner — Story 23.2 PR-4.
/// Aligné sur `FacteurColors.sectionVeille1` (light mode). Le rendu dark
/// reste assuré par les FacteurColors via Theme.of(context).
const Color _kVeilleAccent = Color(0xFF2C3E50);

/// Illustration asset associated with each editorial section.
const String _kEssentielIllustration =
    'assets/notifications/facteur_avatar.png';
const String _kBonnesIllustration = 'assets/notifications/facteur_goodnews.png';
const String _kVeilleIllustration = 'assets/notifications/facteur_veille.png';

/// Blurbs rendered under each section title.
const String _kEssentielBlurb =
    "L'essentiel des actus les plus couvertes en France aujourd'hui, en privilégiant tes sources.";
const String _kActusDuJourBlurb = 'Les sujets les + couverts en France.';
const String _kBonnesBlurb = 'Un peu de douceur...';

/// Hard cap on the number of favorite theme sections rendered in the tournée.
/// Mirrors `kFavoriteCap = 5` in the my_interests provider — the value is
/// duplicated here only because the maps key by sectionKey and we slice the
/// favorite list during composition. Keep aligned with the backend constant.
const int _kMaxFavoriteSections = 5;

/// Hard cap on the number of favorite SOURCE sections rendered in the tournée
/// (PR « Sources dans la Tournée »). Parité avec les thèmes.
const int _kMaxFavoriteSourceSections = 5;

/// Number of items requested per page for each theme section of the Tournée
/// (initial load + each "loadMoreTheme" call). When the backend returns
/// strictly fewer items than this, [_buildThemeSection] forces hasMore=false —
/// no subsequent page can exist regardless of what the backend's
/// pagination.hasNext (computed from a pre-compression candidate count) says.
const int _kThemeSectionPageLimit = 10;

/// Riverpod provider for the Flux Continu V1.8 home screen.
///
/// Orchestrates three parallel API calls at mount (digest, top-themes,
/// essentiel) then up to three themed feed calls once the user's favorites
/// have been resolved. Holds an ordered list of sections (already accounting
/// for the serein swap). The Explorer continuation rendered below the closing
/// card is sourced from `feedProvider` so the filter chips in the Explorer
/// sticky bar actually shape the list.
final fluxContinuProvider =
    AsyncNotifierProvider<FluxContinuNotifier, FluxContinuState>(
  FluxContinuNotifier.new,
);

class FluxContinuNotifier extends AsyncNotifier<FluxContinuState> {
  late DigestRepository _digestRepo;
  late FeedRepository _feedRepo;
  late FluxContinuRepository _fluxRepo;
  late EssentielRepository _essentielRepo;
  late FluxContinuCacheService _cacheService;

  FluxSection? _essentiel;
  // Section "Actus du jour" : DigestTopicSection legacy (kind=essentiel)
  // restaurée après le hotfix Story 9.2 — la nouvelle EssentielSection
  // (carte hi-fi v3) occupe désormais le nom "L'Essentiel du jour" et
  // celle-ci reprend les topics du digest sous le nouveau nom.
  FluxSection? _actusDuJour;
  FluxSection? _bonnes;
  // Up to [_kMaxFavoriteSections] theme/topic sections, ordered to mirror
  // `userInterestsProvider.favorites`. Empty when the user has no favorites
  // — the tournée then collapses to digest only.
  List<FeedThemeSection> _themes = const [];
  // Up to [_kMaxFavoriteSourceSections] source sections (PR « Sources dans la
  // Tournée »), résolues depuis `userSourcesStateProvider.favorites` +
  // catalogue `userSourcesProvider`. Composées entre les thèmes et la veille.
  List<FeedThemeSection> _sources = const [];
  // Dernières sources favorites (sourceId+position) rendues — sert au listener
  // `userSourcesStateProvider` pour ne refetch que sur un vrai changement.
  List<SourceFavoriteRef> _lastSourceFavorites = const [];
  Map<String, bool> _moreOpen = const {};
  bool _closingDismissed = false;
  // Citation du jour servie par le backend (sérène ou normal — même pool
  // YAML, sélection déterministe seed = user_id + date). Rendue avant
  // ClosingCardV18 comme clôture éditoriale de la tournée.
  QuoteResponse? _quote;
  final Set<String> _dismissedIds = <String>{};

  bool _closingPersistQueued = false;

  /// Snapshot of the favorite order we last fetched for. Used by the
  /// userInterestsProvider listener to detect changes and refetch only the
  /// theme sections (cheap) instead of the full tournée.
  List<FavoriteRef> _lastFavorites = const [];

  @override
  Future<FluxContinuState> build() async {
    _digestRepo = ref.read(digestRepositoryProvider);
    _feedRepo = ref.read(feedRepositoryProvider);
    _fluxRepo = ref.read(fluxContinuRepositoryProvider);
    _essentielRepo = ref.read(essentielRepositoryProvider);
    _cacheService = FluxContinuCacheService();

    ref.listen<SereinToggleState>(sereinToggleProvider, (prev, next) {
      if (prev?.enabled != next.enabled && state.hasValue) {
        ref.invalidateSelf();
      }
    });

    // React to favorite reorders / additions / removals without rebuilding
    // the digest (the digest doesn't depend on favorites).
    ref.listen<AsyncValue<UserInterestsState>>(userInterestsProvider, (
      prev,
      next,
    ) {
      final nextFavorites = next.valueOrNull?.favorites;
      if (nextFavorites == null) return;
      final picked = _pickExplicitFavorites(nextFavorites);
      if (_favoriteListsEqual(_lastFavorites, picked)) return;
      if (!state.hasValue) return;
      unawaited(_refetchThemesOnly(picked));
    });

    // PR « Sources dans la Tournée » — réagit à l'ajout/retrait/réordre d'une
    // source favorite en ne refetchant QUE les sections source (le digest et
    // les thèmes ne dépendent pas des sources favorites).
    ref.listen<AsyncValue<UserSourcesState>>(userSourcesStateProvider, (
      prev,
      next,
    ) {
      final nextFavorites = next.valueOrNull?.favorites;
      if (nextFavorites == null) return;
      final picked = _pickFavoriteSources(nextFavorites);
      if (_sourceFavoritesEqual(_lastSourceFavorites, picked)) return;
      if (!state.hasValue) return;
      unawaited(_refetchSourcesOnly(picked));
    });

    // Story 10.2 — `tournee_order_v1` fait autorité pour le **mode** des sources :
    // une source y figure ⇒ mode « Essentiel ». Deux cas à distinguer ici :
    //  - l'ensemble des clés `source:` de l'ordre change (une source entre ou
    //    sort de l'Essentiel) ⇒ il faut **refetch** : une source qui entre
    //    n'existe pas encore dans `_sources` ; une qui sort doit en disparaître.
    //  - sinon (réordre/masques) ⇒ simple recompose (sections déjà fetchées).
    ref.listen<TourneeOrderState>(tourneeOrderPrefsProvider, (prev, next) {
      if (!state.hasValue) return;
      if (prev != null &&
          listEquals(prev.order, next.order) &&
          setEquals(prev.hiddenKeys, next.hiddenKeys)) {
        return;
      }
      final prevSourceKeys = prev?.essentielSourceKeys ?? const <String>{};
      if (!setEquals(prevSourceKeys, next.essentielSourceKeys)) {
        unawaited(_refetchSourcesOnly(_pickFavoriteSources()));
        return;
      }
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    // Story Essentiel UX — modèle exclusif thèmes : quand un thème entre/sort
    // des onglets Flâner (`pinned_tabs_order_v1`), il doit (dis)paraître des
    // sections Essentiel. On recompose seulement quand l'ensemble des clés
    // `theme:` change (un réordre sujets/sources Flâner n'affecte pas la Tournée).
    ref.listen<List<String>>(tabOrderPrefsProvider, (prev, next) {
      if (!state.hasValue) return;
      Set<String> themeKeys(List<String>? keys) => {
            for (final k in keys ?? const <String>[])
              if (k.startsWith('theme:')) k,
          };
      if (setEquals(themeKeys(prev), themeKeys(next))) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    // La Grille est un slot autonome dans la liste cappée : sa présence dépend
    // uniquement de `today != null`, pas des sections déjà fetchées.
    ref.listen<AsyncValue<GrilleState>>(grilleProvider, (prev, next) {
      if (!state.hasValue) return;
      final wasPresent = prev?.valueOrNull?.today != null;
      final isPresent = next.valueOrNull?.today != null;
      if (wasPresent == isPresent) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    final cached = await _cacheService.readToday();
    if (cached != null) {
      state = AsyncData(
        await _buildStateFromPayload(
          dual: cached.dual,
          topThemes: cached.topThemes,
          essentielArticles: cached.essentielArticles,
          isSerene: ref.read(sereinToggleProvider).enabled,
          fetchThemes: false,
        ),
      );
    }

    return _fetchAll();
  }

  Future<FluxContinuState> _fetchAll() async {
    final isSerene = ref.read(sereinToggleProvider).enabled;

    final results = await Future.wait([
      _safe<DualDigestResponse>(
        () => _digestRepo.fetchBothDigests(),
        'fetchBothDigests',
      ),
      _safe<List<TopTheme>>(
        () => _fluxRepo.getTopThemes(),
        'getTopThemes',
        fallback: const <TopTheme>[],
      ),
      _safe<List<EssentielArticle>>(
        () async => (await _essentielRepo.fetch()) ?? const [],
        'fetchEssentiel',
        fallback: const <EssentielArticle>[],
      ),
    ]);
    final dual = results[0] as DualDigestResponse?;
    final topThemes = (results[1] as List<TopTheme>?) ?? const <TopTheme>[];
    final essentielArticles =
        (results[2] as List<EssentielArticle>?) ?? const <EssentielArticle>[];

    final next = await _buildStateFromPayload(
      dual: dual,
      topThemes: topThemes,
      essentielArticles: essentielArticles,
      isSerene: isSerene,
      fetchThemes: true,
    );
    if (dual != null) {
      unawaited(
        _cacheService.write(
          dual: dual,
          topThemes: topThemes,
          essentielArticles: essentielArticles,
        ),
      );
      // Re-pose les notifs perso (Essentiel + Bonnes Nouvelles) avec le contenu
      // frais. Fire-and-forget, gated sur `dual != null` → ne tire jamais sur le
      // chemin caché (stale) ni quand le digest a totalement échoué.
      unawaited(_syncNotificationTeasers(dual, essentielArticles));
    }
    return next;
  }

  /// Pousse les derniers teasers connus vers `NotificationsSettingsNotifier`
  /// pour re-planifier les notifs perso. Non bloquant, try/catch interne : une
  /// erreur de scheduling ne doit jamais casser le rendu du home.
  Future<void> _syncNotificationTeasers(
    DualDigestResponse dual,
    List<EssentielArticle> essentielArticles,
  ) async {
    try {
      await ref.read(notificationsSettingsProvider.notifier).syncDigestTeasers(
            essentielTeasers: buildEssentielTeasers(essentielArticles),
            goodNewsTeasers: buildGoodNewsTeasers(dual.serein),
          );
    } catch (e) {
      debugPrint('FluxContinu: syncNotificationTeasers failed: $e');
    }
  }

  Future<FluxContinuState> _buildStateFromPayload({
    required DualDigestResponse? dual,
    required List<TopTheme> topThemes,
    required List<EssentielArticle> essentielArticles,
    required bool isSerene,
    required bool fetchThemes,
  }) async {
    // PR2 — la section "Essentiel" du haut du feed est désormais alimentée
    // par GET /api/essentiel (5 articles transversaux). Si l'endpoint n'a
    // rien servi (preparing/erreur), on ne rend pas la section : le digest
    // legacy reste affiché juste en dessous sous le nom "Actus du jour",
    // et Bonnes Nouvelles n'est pas affectée.
    _essentiel = _buildEssentielSection(essentielArticles);
    // Hotfix Story 9.2 — "Actus du jour" : DigestTopicSection legacy,
    // alimentée par `dual.normal` (digest classique), avec le label
    // historique "Actus du jour" (anciennement "L'Essentiel du jour" avant
    // que la carte hi-fi v3 ne reprenne ce nom).
    _actusDuJour = _buildDigestSection(
      digest: dual?.normal,
      kind: SectionKind.essentiel,
      label: 'Actus du jour',
      blurb: _kActusDuJourBlurb,
      accent: _kEssentielAccent,
      illustration: _kEssentielIllustration,
      coreVisibleCount: 3,
    );
    _bonnes = _buildDigestSection(
      digest: dual?.serein,
      kind: SectionKind.bonnes,
      label: 'Bonnes Nouvelles',
      blurb: _kBonnesBlurb,
      accent: _kBonnesAccent,
      illustration: _kBonnesIllustration,
      coreVisibleCount: isSerene ? 4 : 2,
    );
    // Citation du jour — même pool dans les deux digests (déterministe par
    // user/date), on prend le sérène par défaut et on retombe sur le normal
    // si seul l'un des deux a réussi.
    _quote = dual?.serein?.quote ?? dual?.normal?.quote;

    final picked = _pickFavorites(topThemes);
    final favorites = picked.refs;
    _lastFavorites = favorites;
    final favoriteSources = _pickFavoriteSources();
    _lastSourceFavorites = favoriteSources;
    final fetched = fetchThemes
        ? await Future.wait([
            _fetchThemeSections(
              favorites,
              isSerene,
              isExplicitFavorite: !picked.isFallback,
            ),
            _fetchSourceSections(favoriteSources, isSerene),
          ])
        : const [<FeedThemeSection>[], <FeedThemeSection>[]];
    _themes = fetched[0];
    _sources = fetched[1];

    _moreOpen = const {};
    _closingDismissed = await _loadClosingDismissedForToday();
    unawaited(_purgeOldPrefsKeys());

    return _compose(isSerene);
  }

  FluxContinuState _compose(bool isSerene) {
    final tournee = ref.read(tourneeOrderPrefsProvider);
    final grilleAvailable = ref.read(grilleProvider).valueOrNull?.today != null;
    final sectionByKey = _tourneeSectionByKey();
    final orderedKeys = _orderedTourneeKeys(
      isSerene: isSerene,
      customized: tournee.customized,
      sectionByKey: sectionByKey,
      grilleAvailable: grilleAvailable,
      hiddenKeys: tournee.hiddenKeys,
      order: tournee.order,
    );

    final rawOrdered = <FluxSection>[
      if (_essentiel != null) _essentiel!,
      for (final key in orderedKeys)
        if (key != kTourneeGrilleKey && sectionByKey[key] != null)
          sectionByKey[key]!,
    ];
    final finalSections = _dedupeSectionsInOrder(_filterSections(rawOrdered));
    final grilleSlotIndex = _resolveGrilleSlotIndex(
      orderedKeys: orderedKeys,
      finalSections: finalSections,
    );

    // Drop moreOpen entries pointing at sections that didn't survive
    // composition (e.g. a favorite was removed since it was opened earlier).
    // Keeps the map tight and avoids stale ghosts.
    final keysPresent = finalSections.map(sectionKey).toSet();
    final moreOpenFiltered = <String, bool>{
      for (final entry in _moreOpen.entries)
        if (entry.value && keysPresent.contains(entry.key)) entry.key: true,
    };
    if (moreOpenFiltered.length != _moreOpen.length) {
      _moreOpen = moreOpenFiltered;
    }

    return FluxContinuState(
      sections: finalSections,
      grilleSlotIndex: grilleSlotIndex,
      isSerene: isSerene,
      moreOpen: _moreOpen,
      closingDismissed: _closingDismissed,
      dismissedIds: Set.unmodifiable(_dismissedIds),
      quote: _quote,
      isLoading: false,
    );
  }

  /// Fires the backend "hide" API for the article without touching local
  /// state. Used the moment the user swipes a card: the card position is
  /// momentarily kept (replaced by an inline feedback banner managed by the
  /// screen), so we don't want the provider to purge the article yet.
  Future<void> markHiddenRemote(String contentId) async {
    if (contentId.isEmpty) return;
    try {
      await _feedRepo.hideContent(contentId);
    } catch (e) {
      debugPrint('FluxContinu: markHiddenRemote failed for $contentId: $e');
    }
  }

  /// Purges the article from the local state — adds the id to the dismissed
  /// set and re-emits filtered sections. No API call (the hide was already
  /// fired via [markHiddenRemote] at swipe time). The Explorer continuation
  /// reads its items from `feedProvider`, so the screen layer applies the
  /// same `dismissedIds` filter there. Called when the user resolves the
  /// inline feedback (chip / close / viewport-exit).
  void confirmDismiss(String contentId) {
    if (contentId.isEmpty) return;
    if (_dismissedIds.contains(contentId)) return;
    _dismissedIds.add(contentId);
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        sections: _filterSections(current.sections),
        dismissedIds: Set.unmodifiable(_dismissedIds),
      ),
    );
  }

  /// Restores an article that was hidden remotely but not yet purged from
  /// local state (i.e. the user tapped "Annuler" on the inline feedback).
  /// Fire-and-forget — the article is still in [state], so the card will
  /// reappear in place as soon as the screen clears its pending entry.
  Future<void> undoHide(String contentId) async {
    if (contentId.isEmpty) return;
    try {
      await _feedRepo.unhideContent(contentId);
    } catch (e) {
      debugPrint('FluxContinu: undoHide failed for $contentId: $e');
    }
  }

  /// Backwards-compatible facade for the "no feedback" swipe path: fires the
  /// hide API and purges from state in one go. Retained so call-sites that
  /// don't need the inline feedback flow keep working.
  Future<void> dismissArticle(String contentId) async {
    confirmDismiss(contentId);
    await markHiddenRemote(contentId);
  }

  List<FluxSection> _filterSections(List<FluxSection> sections) {
    if (_dismissedIds.isEmpty) return sections;
    return [
      for (final s in sections)
        switch (s) {
          EssentielSection(:final articles) => EssentielSection(
              articles: articles
                  .where((a) => !_dismissedIds.contains(a.contentId))
                  .toList(growable: false),
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
            ),
          DigestTopicSection(:final topics) => DigestTopicSection(
              kind: s.kind,
              label: s.label,
              accent: s.accent,
              coreVisibleCount: s.coreVisibleCount,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
              topics: topics
                  .where(
                    (t) => !_dismissedIds.contains(pickTopicLead(t).contentId),
                  )
                  .toList(growable: false),
            ),
          // copyWith préserve tous les champs (themeSlug/customTopicId/
          // sourceId/sourceLogoUrl/pagination) — ne reconstruis pas à la main
          // sous peine de perdre les champs source des sections Tournée.
          FeedThemeSection(:final items) => s.copyWith(
              items: items
                  .where((c) => !_dismissedIds.contains(c.id))
                  .toList(growable: false),
            ),
        },
    ];
  }

  /// Dedup inter-sections ordonné : parcourt les sections dans l'ordre de
  /// rendu et retire de chaque section les articles déjà vus plus haut. La
  /// première section qui contient un article « gagne » — en mode normal
  /// Essentiel est premier, donc il prive Actus du jour / thèmes de ses
  /// doublons (Option A : pour un sujet digest, la tête déjà vue retire le
  /// sujet entier).
  ///
  /// Identité par type, cohérente avec [renderedContentIds] / [_filterSections] :
  ///   - [EssentielSection] → `article.contentId`
  ///   - [DigestTopicSection] → `pickTopicLead(t).contentId`
  ///   - [FeedThemeSection] → `content.id`
  ///
  /// Tourne à chaque [_compose] (contrairement à [_filterSections] qui ne
  /// tourne que si des articles ont été dismissed), donc les champs de
  /// pagination de [FeedThemeSection] sont préservés via [FeedThemeSection.copyWith]
  /// — sinon « Voir +10 » serait réinitialisé à chaque recompose.
  List<FluxSection> _dedupeSectionsInOrder(List<FluxSection> sections) {
    final seen = <String>{};
    final result = <FluxSection>[];
    for (final s in sections) {
      switch (s) {
        case EssentielSection(:final articles):
          result.add(
            EssentielSection(
              articles: articles
                  .where((a) => seen.add(a.contentId))
                  .toList(growable: false),
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
            ),
          );
        case DigestTopicSection(:final topics):
          final kept = topics
              .where((t) => seen.add(pickTopicLead(t).contentId))
              .toList(growable: false);
          // Post-filtre : une section Actus du jour vidée par le dedup ne doit
          // pas laisser un bandeau orphelin → on la retire.
          if (kept.isEmpty) continue;
          result.add(
            DigestTopicSection(
              kind: s.kind,
              label: s.label,
              accent: s.accent,
              coreVisibleCount: s.coreVisibleCount,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
              topics: kept,
            ),
          );
        case FeedThemeSection(:final items):
          result.add(
            s.copyWith(
              items: items.where((c) => seen.add(c.id)).toList(growable: false),
            ),
          );
      }
    }
    return result;
  }

  /// Marks a single article as read in-memory (same-session visual feedback).
  ///
  /// Called by [FluxContinuScreen._openArticle] after the reader route pops so
  /// the card immediately shows the grey + check badge without waiting for a
  /// pull-to-refresh. No API call — the reader already fires the status update
  /// independently.
  void markArticleRead(String contentId) {
    if (contentId.isEmpty) return;
    final current = state.valueOrNull;
    if (current == null) return;
    final updated = [
      for (final s in current.sections)
        switch (s) {
          EssentielSection(:final articles) => EssentielSection(
              articles: [
                for (final a in articles)
                  if (a.contentId == contentId)
                    EssentielArticle(
                      contentId: a.contentId,
                      title: a.title,
                      url: a.url,
                      thumbnailUrl: a.thumbnailUrl,
                      publishedAt: a.publishedAt,
                      sourceName: a.sourceName,
                      sourceLetter: a.sourceLetter,
                      sectionLabel: a.sectionLabel,
                      rank: a.rank,
                      kind: a.kind,
                      theme: a.theme,
                      perspectiveCount: a.perspectiveCount,
                      isRead: true,
                      isSaved: a.isSaved,
                      isLiked: a.isLiked,
                      isDismissed: a.isDismissed,
                      isFollowedSource: a.isFollowedSource,
                      isFollowedTopic: a.isFollowedTopic,
                      isActuDuJour: a.isActuDuJour,
                    )
                  else
                    a,
              ],
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
            ),
          DigestTopicSection(:final topics) => DigestTopicSection(
              kind: s.kind,
              label: s.label,
              accent: s.accent,
              coreVisibleCount: s.coreVisibleCount,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
              topics: [
                for (final t in topics)
                  t.copyWith(
                    articles: [
                      for (final a in t.articles)
                        if (a.contentId == contentId)
                          a.copyWith(isRead: true)
                        else
                          a,
                    ],
                  ),
              ],
            ),
          FeedThemeSection(
            :final items,
            :final themeSlug,
            :final customTopicId,
          ) =>
            FeedThemeSection(
              kind: s.kind,
              label: s.label,
              accent: s.accent,
              coreVisibleCount: s.coreVisibleCount,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
              themeSlug: themeSlug,
              customTopicId: customTopicId,
              items: [
                for (final c in items)
                  if (c.id == contentId)
                    c.copyWith(status: ContentStatus.consumed)
                  else
                    c,
              ],
            ),
        },
    ];
    state = AsyncData(current.copyWith(sections: updated));
  }

  /// Toggle the expand/collapse state of a section's "Plus de…" overflow.
  void toggleMore(FluxSection section) {
    final current = state.valueOrNull;
    if (current == null) return;
    final key = sectionKey(section);
    final next = Map<String, bool>.from(_moreOpen);
    next[key] = !(next[key] ?? false);
    _moreOpen = next;
    state = AsyncData(current.copyWith(moreOpen: next));
  }

  /// In-place pagination for the Tournée du jour theme sections. Fetches the
  /// next page from `/api/feed?theme=…&personalized=true` (or topic UUID for
  /// custom topics) and appends it to the section's [FeedThemeSection.items]
  /// — same backend curation as the initial load, so users only see articles
  /// from sources they follow, within the last 24h.
  ///
  /// No-op when the section is not in [state.sections], is already loading,
  /// or the backend reported no more pages.
  Future<void> loadMoreTheme(String key) async {
    final current = state.valueOrNull;
    if (current == null) return;
    final idx = current.sections.indexWhere(
      (s) => s is FeedThemeSection && sectionKey(s) == key,
    );
    if (idx < 0) return;
    final target = current.sections[idx] as FeedThemeSection;
    if (target.isLoadingMore || !target.hasMore) return;

    final loading = target.copyWith(isLoadingMore: true);
    final loadingSections = List<FluxSection>.from(current.sections)
      ..[idx] = loading;
    state = AsyncData(current.copyWith(sections: loadingSections));

    final isSerene = current.isSerene;
    final nextPage = target.currentPage + 1;
    final FeedResponse? response;
    if (target.kind == SectionKind.veille) {
      // La veille pagine via /api/veille/feed (offset), PAS via le feed général
      // personnalisé : ce dernier injectait des articles hors-veille en fin de
      // section et déclenchait tout le pipeline de reco (plan V0, Pb 2&3).
      final offset = (nextPage - 1) * _kThemeSectionPageLimit;
      response = await _safe<FeedResponse>(
        () => ref.read(fluxContinuRepositoryProvider).getVeilleFeedItems(
              limit: _kThemeSectionPageLimit,
              offset: offset,
              serein: isSerene,
            ),
        'loadMoreTheme(veille offset=$offset)',
      );
    } else {
      final theme = target.themeSlug;
      final topic = target.customTopicId;
      response = await _safe<FeedResponse>(
        () => _feedRepo.getFeed(
          page: nextPage,
          limit: _kThemeSectionPageLimit,
          theme: theme,
          topic: topic,
          serein: isSerene,
          personalized: true,
        ),
        'loadMoreTheme($key)',
      );
    }

    // Re-read state in case it shifted while the request was in flight.
    final afterCurrent = state.valueOrNull;
    if (afterCurrent == null) return;
    final afterIdx = afterCurrent.sections.indexWhere(
      (s) => s is FeedThemeSection && sectionKey(s) == key,
    );
    if (afterIdx < 0) return;
    final afterTarget = afterCurrent.sections[afterIdx] as FeedThemeSection;

    final FeedThemeSection updated;
    if (response == null || response.items.isEmpty) {
      // Treat empty/error response as "no more" so the button settles into
      // the disabled "Plus rien à voir" state rather than spinning forever.
      updated = afterTarget.copyWith(isLoadingMore: false, hasMore: false);
    } else {
      // Dedupe by content id — guards against a new article being published
      // between page 1 and page 2 and shifting the chronological cursor.
      final existingIds = {for (final item in afterTarget.items) item.id};
      final appended = [
        ...afterTarget.items,
        for (final item in response.items)
          if (!existingIds.contains(item.id)) item,
      ];
      final hasMore = _themeHasMore(
        response.pagination.hasNext,
        response.items.length,
      );
      updated = afterTarget.copyWith(
        items: appended,
        currentPage: nextPage,
        hasMore: hasMore,
        isLoadingMore: false,
      );
    }
    final nextSections = List<FluxSection>.from(afterCurrent.sections)
      ..[afterIdx] = updated;
    state = AsyncData(afterCurrent.copyWith(sections: nextSections));
  }

  /// Dismisses the closing card "Vous êtes à jour" for the day. Triggered
  /// by the Continuer/Refermer CTAs. Idempotent.
  Future<void> markClosingDismissed() async {
    final current = state.valueOrNull;
    if (current == null) return;
    if (current.closingDismissed) return;
    _closingDismissed = true;
    state = AsyncData(current.copyWith(closingDismissed: true));
    await _persistClosingDismissed(true);
  }

  /// Records the closing-card dismissal for the next session without hiding it
  /// now: it stays visible this session and only loads dismissed on the next
  /// cold launch, so the user never sees it disappear mid-scroll.
  Future<void> markClosingDismissedForNextSession() async {
    if (_closingPersistQueued || _closingDismissed) return;
    _closingPersistQueued = true;
    await _persistClosingDismissed(true);
  }

  Future<bool> _loadClosingDismissedForToday() async {
    return ref
        .read(tourneeProgressServiceProvider)
        .loadClosingDismissedForToday();
  }

  Future<void> _persistClosingDismissed(bool dismissed) async {
    await ref
        .read(tourneeProgressServiceProvider)
        .setClosingDismissedToday(dismissed);
  }

  Future<void> _purgeOldPrefsKeys() async {
    await ref.read(tourneeProgressServiceProvider).purgeOldPrefsKeys();
  }

  /// Pull-to-refresh: refetch all upstream calls from scratch.
  ///
  /// Crucially we do NOT bounce through [AsyncLoading] — doing so would
  /// tear down the [RefreshIndicator] mid-pull (the screen renders the
  /// loading skeleton in place of the scroll view), making the gesture
  /// feel broken. Keeping the previous data mounted lets the native
  /// indicator stay visible until the refetch resolves.
  Future<void> refresh() async {
    final next = await AsyncValue.guard(_fetchAll);
    state = next;
  }

  /// Builds the v3 "L'Essentiel du jour" hi-fi section from the 5 articles
  /// returned by `GET /api/essentiel`. Returns `null` when the endpoint hasn't
  /// produced anything yet (202 preparing or transient failure) so the screen
  /// degrades gracefully — Bonnes Nouvelles + thèmes restent visibles.
  FluxSection? _buildEssentielSection(List<EssentielArticle> articles) {
    if (articles.isEmpty) return null;
    return EssentielSection(
      articles: articles,
      illustrationAsset: _kEssentielIllustration,
      blurb: _kEssentielBlurb,
    );
  }

  FluxSection? _buildDigestSection({
    required DigestResponse? digest,
    required SectionKind kind,
    required String label,
    required String blurb,
    required Color accent,
    required String illustration,
    required int coreVisibleCount,
  }) {
    final topics = digest?.topics
            .where((t) => t.articles.isNotEmpty)
            .toList(growable: false) ??
        const <DigestTopic>[];
    if (topics.isEmpty) return null;
    return DigestTopicSection(
      kind: kind,
      label: label,
      blurb: blurb,
      accent: accent,
      illustrationAsset: illustration,
      coreVisibleCount: coreVisibleCount,
      topics: topics,
    );
  }

  /// Returns true when more theme pages exist. Guards against the backend's
  /// total_candidates being computed before compression layers — a partial page
  /// (< limit) is definitive proof that no next page exists regardless of
  /// pagination.hasNext.
  bool _themeHasMore(bool hasNext, int itemCount) =>
      hasNext && itemCount >= _kThemeSectionPageLimit;

  /// Builds a FeedThemeSection from a fetched payload. The label/accent come
  /// from the canonical theme visual mapping for Theme favorites; for custom
  /// topic (Sujet) favorites the caller passes the user's topic name.
  ///
  /// [isExplicitFavorite] : un favori thème **explicite** n'est jamais coupé
  /// (miroir de [_buildSourceSection] : ne jamais masquer un favori — l'état
  /// vide est rendu par SectionBlock). Un thème **de fallback** (compte neuf)
  /// reste coupé sous 2 items pour ne pas afficher un empty-state canonique
  /// que l'utilisateur n'a pas choisi.
  FeedThemeSection? _buildThemeSection({
    required FeedResponse? feed,
    required String label,
    required Color accent,
    required bool isExplicitFavorite,
    String? themeSlug,
    String? customTopicId,
  }) {
    final items = feed?.items ?? const <Content>[];
    if (!isExplicitFavorite && items.length < 2) return null;
    final hasMore = _themeHasMore(
      feed?.pagination.hasNext ?? false,
      items.length,
    );
    return FeedThemeSection(
      kind: SectionKind.theme,
      label: label,
      accent: accent,
      illustrationAsset: _kVeilleIllustration,
      coreVisibleCount: 3,
      themeSlug: themeSlug,
      customTopicId: customTopicId,
      items: items,
      hasMore: hasMore,
    );
  }

  /// Resolves the ordered list of favorite refs to render as theme sections.
  ///
  /// Source of truth: `userInterestsProvider.favorites` (the user-declared
  /// favorites, cap = [_kMaxFavoriteSections]). Fallback when the provider
  /// hasn't loaded yet OR returned an empty list: the legacy `top-themes`
  /// endpoint (weight-based) capped to 5 entries, then canonical macro
  /// themes. This guarantees fresh accounts always see a tournée even before
  /// the backfill migration runs.
  ///
  /// Le fallback canonique est **gaté** sur un compte réellement neuf
  /// (`!customized && pas de source favorite && pas de veille`) : sans ça, un
  /// retrait volontaire de tous les thèmes se faisait ré-injecter au prochain
  /// reload (cold start / pull-to-refresh / toggle serein / invalidateSelf).
  ///
  /// `isFallback` indique si les `refs` thème renvoyés sont des thèmes canoniques
  /// (compte neuf) plutôt que des favoris explicites — consommé par
  /// [_fetchThemeSections] pour décider de l'affichage d'un empty-state.
  ({List<FavoriteRef> refs, bool isFallback}) _pickFavorites(
    List<TopTheme> topFallback,
  ) {
    final favorites =
        ref.read(userInterestsProvider).valueOrNull?.favorites ?? const [];

    // Story 23.4 — la veille a un **slot dédié hors cap** : on la sépare des
    // favoris thème/sujet (cap = [_kMaxFavoriteSections]) puis on l'ajoute en
    // plus, pour qu'elle ne soit jamais coupée par le cap thème/source.
    VeilleFavoriteRef? veilleRef;
    final nonVeille = <FavoriteRef>[];
    for (final f in favorites) {
      if (f is VeilleFavoriteRef) {
        veilleRef ??= f;
      } else if (f is CustomTopicFavoriteRef) {
        continue; // PR 2 : sujets perso = Flâner-only, hors Tournée (PO 5)
      } else {
        nonVeille.add(f);
      }
    }
    // Toujours rendre la veille quand une config est active, même si le favori
    // n'est pas (encore) dans la liste (favori orphelin / self-heal en cours).
    final activeCfg = ref.read(veilleActiveConfigProvider).valueOrNull;
    if (veilleRef == null && activeCfg != null) {
      veilleRef = VeilleFavoriteRef(id: activeCfg.id);
    }

    final List<FavoriteRef> themeRefs;
    var isFallback = false;
    if (nonVeille.isNotEmpty) {
      themeRefs = nonVeille.take(_kMaxFavoriteSections).toList(growable: false);
    } else {
      // Fallback canonique réservé aux comptes réellement neufs : pas de retrait
      // volontaire enregistré, pas de source favorite, pas de veille. Sinon on
      // respecte la Tournée vide / source-only (on peut descendre à 0 thème).
      final customized = ref.read(tourneeOrderPrefsProvider).customized;
      final hasSourceFav = ref
              .read(userSourcesStateProvider)
              .valueOrNull
              ?.favorites
              .isNotEmpty ??
          false;
      if (customized || hasSourceFav || veilleRef != null) {
        themeRefs = const [];
      } else {
        // Fallback fresh accounts : top-themes pondérés puis macro canoniques.
        final valid = topFallback
            .where((t) => themeMap.containsKey(t.interestSlug))
            .map<FavoriteRef>((t) => ThemeFavoriteRef(slug: t.interestSlug))
            .toList();
        // Pad with canonical macro themes the user is missing — order: tech,
        // environment, science (matches the backend backfill list).
        const canonical = [fallbackTheme1, fallbackTheme2, 'science'];
        final present =
            valid.whereType<ThemeFavoriteRef>().map((r) => r.slug).toSet();
        for (final slug in canonical) {
          if (valid.length >= _kMaxFavoriteSections) break;
          if (present.contains(slug)) continue;
          valid.add(ThemeFavoriteRef(slug: slug));
          present.add(slug);
        }
        themeRefs = valid.take(_kMaxFavoriteSections).toList(growable: false);
        isFallback = themeRefs.isNotEmpty;
      }
    }

    return (
      refs: [...themeRefs, if (veilleRef != null) veilleRef],
      isFallback: isFallback,
    );
  }

  /// Fetches one FeedResponse per favorite ref in parallel and turns them
  /// into FeedThemeSections. Un favori thème **explicite**
  /// ([isExplicitFavorite] = true) est toujours rendu (empty-state si vide) ;
  /// les thèmes de **fallback** (compte neuf) sont coupés sous 2 items pour
  /// garder la Tournée par défaut utile sans afficher d'empty-state non choisi.
  Future<List<FeedThemeSection>> _fetchThemeSections(
    List<FavoriteRef> favorites,
    bool isSerene, {
    bool isExplicitFavorite = true,
  }) async {
    if (favorites.isEmpty) return const [];
    final interestsState = ref.read(userInterestsProvider).valueOrNull;
    final feeds = await Future.wait(
      favorites.map((favRef) => _fetchOneTheme(favRef, isSerene)),
    );
    final sections = <FeedThemeSection>[];
    for (var i = 0; i < favorites.length; i++) {
      final favRef = favorites[i];
      final feed = feeds[i];
      final section = switch (favRef) {
        ThemeFavoriteRef(:final slug) => _buildThemeSection(
            feed: feed,
            label: visualFor(slug).label,
            accent: visualFor(slug).accent,
            themeSlug: slug,
            isExplicitFavorite: isExplicitFavorite,
          ),
        CustomTopicFavoriteRef(:final id) => _buildThemeSection(
            feed: feed,
            label: _customTopicLabel(interestsState, id),
            accent: _customTopicAccent(interestsState, id),
            customTopicId: id,
            isExplicitFavorite: isExplicitFavorite,
          ),
        // Story 23.2 PR-4 : la veille devient une section Tournée dédiée
        // avec son propre accent et label, calculée séparément des thèmes.
        VeilleFavoriteRef() => _buildVeilleSection(feed),
      };
      if (section != null) sections.add(section);
    }
    return sections;
  }

  List<FavoriteRef> _pickExplicitFavorites(List<FavoriteRef> favorites) {
    VeilleFavoriteRef? veilleRef;
    final nonVeille = <FavoriteRef>[];
    for (final favorite in favorites) {
      if (favorite is VeilleFavoriteRef) {
        veilleRef ??= favorite;
      } else if (favorite is CustomTopicFavoriteRef) {
        continue;
      } else {
        nonVeille.add(favorite);
      }
    }
    return [
      ...nonVeille.take(_kMaxFavoriteSections),
      if (veilleRef != null) veilleRef,
    ];
  }

  Future<FeedResponse?> _fetchOneTheme(FavoriteRef favRef, bool isSerene) {
    // `personalized: true` flips the backend to "followed sources only +
    // 24h window + user_subtopics boost" for the Tournée du jour theme
    // sections (vs. the unrestricted exploration mode used by feed chips).
    return switch (favRef) {
      ThemeFavoriteRef(:final slug) => _safe<FeedResponse>(
          () => _feedRepo.getFeed(
            page: 1,
            limit: _kThemeSectionPageLimit,
            theme: slug,
            serein: isSerene,
            personalized: true,
          ),
          'getFeed?theme=$slug&personalized=true',
        ),
      // Backend `/api/feed` accepts a UUID stringified in the `topic` param
      // (story 22.1) — looked up against `user_topic_profiles` scoped on the
      // current user, so no cross-user leak.
      CustomTopicFavoriteRef(:final id) => _safe<FeedResponse>(
          () => _feedRepo.getFeed(
            page: 1,
            limit: _kThemeSectionPageLimit,
            topic: id,
            serein: isSerene,
            personalized: true,
          ),
          'getFeed?topic=$id&personalized=true',
        ),
      // Story 23.2 PR-4 : la veille est résolue via `/api/veille/feed`,
      // exposée par FluxContinuRepository.getVeilleFeedItems (normalise la
      // réponse en FeedResponse Content-compatible).
      VeilleFavoriteRef() => _safe<FeedResponse>(
          () => ref.read(fluxContinuRepositoryProvider).getVeilleFeedItems(
                limit: _kThemeSectionPageLimit,
                serein: isSerene,
              ),
          'getVeilleFeedItems',
        ),
    };
  }

  /// Construit la section veille — accent dédié `sectionVeille1` + label
  /// dérivé du `theme_label` de la `VeilleConfig` active (résolu via
  /// `veilleActiveConfigProvider`). Story 23.2 PR-4.
  FeedThemeSection? _buildVeilleSection(FeedResponse? feed) {
    final activeCfg = ref.read(veilleActiveConfigProvider).valueOrNull;
    // Story 23.4 — section veille **toujours visible** quand une config est
    // active, même avec 0/1 article (état vide rendu par SectionBlock). On ne
    // la coupe plus sur un seuil min d'items ; `null` seulement sans config.
    if (activeCfg == null) return null;
    final items = feed?.items ?? const <Content>[];
    // hasMore dérivé de la pagination backend (`has_more`), pas du défaut `true`
    // du modèle : sans ça la section se croyait toujours paginable et
    // `loadMoreTheme` partait chercher des articles hors-veille (plan V0, Pb 2&3).
    final hasMore = _themeHasMore(
      feed?.pagination.hasNext ?? false,
      items.length,
    );
    return FeedThemeSection(
      kind: SectionKind.veille,
      label: 'Ma veille — ${activeCfg.themeLabel}',
      blurb: 'Les derniers articles de ta veille personnalisée.',
      accent: _kVeilleAccent,
      illustrationAsset: _kVeilleIllustration,
      coreVisibleCount: 3,
      items: items,
      hasMore: hasMore,
    );
  }

  // ---------------------------------------------------------------------------
  // Sections SOURCE de la Tournée (PR « Sources dans la Tournée »).
  // ---------------------------------------------------------------------------

  /// Sources favorites à rendre comme sections, triées par `position` et capées
  /// à [_kMaxFavoriteSourceSections]. Source de vérité : les `favorites` de
  /// `userSourcesStateProvider` (distinct des thèmes/sujets/veille de
  /// `userInterestsProvider`). Le paramètre optionnel permet au listener de
  /// passer la valeur fraîche avant qu'elle ne soit committée au provider.
  List<SourceFavoriteRef> _pickFavoriteSources([
    List<SourceFavoriteRef>? favorites,
  ]) {
    final favs = favorites ??
        ref.read(userSourcesStateProvider).valueOrNull?.favorites ??
        const <SourceFavoriteRef>[];
    // Story 10.2 — appartenance exclusive : une source n'est rendue dans la
    // Tournée que si elle est en mode « Essentiel » (sa clé `source:<id>` est
    // dans `tournee_order_v1`). Sinon elle vit en mode « Flâner » (onglets).
    // Règle centralisée dans [TourneeOrderState.sourceIsEssentiel].
    final tournee = ref.read(tourneeOrderPrefsProvider);
    final inEssentiel = [
      for (final f in favs)
        if (tournee.sourceIsEssentiel(f.sourceId)) f,
    ]..sort((a, b) => a.position.compareTo(b.position));
    return inEssentiel
        .take(_kMaxFavoriteSourceSections)
        .toList(growable: false);
  }

  /// Résout chaque source favorite en `Source` complet (nom + logo + thème)
  /// via le catalogue `userSourcesProvider`, puis fetch en parallèle le top
  /// classé (mêmes piliers que les thèmes, `personalized: true`). Les favoris
  /// dont la source n'est pas (encore) dans le catalogue sont ignorés ce cycle.
  Future<List<FeedThemeSection>> _fetchSourceSections(
    List<SourceFavoriteRef> favs,
    bool isSerene,
  ) async {
    if (favs.isEmpty) return const [];
    final catalog =
        ref.read(userSourcesProvider).valueOrNull ?? const <Source>[];
    final sourceById = {for (final s in catalog) s.id: s};
    final resolved = <Source>[];
    for (final fav in favs) {
      final src = sourceById[fav.sourceId];
      if (src != null) resolved.add(src);
    }
    if (resolved.isEmpty) return const [];
    final feeds = await Future.wait(
      resolved.map((src) => _fetchOneSource(src.id, isSerene)),
    );
    final sections = <FeedThemeSection>[];
    for (var i = 0; i < resolved.length; i++) {
      final section = _buildSourceSection(feed: feeds[i], source: resolved[i]);
      if (section != null) sections.add(section);
    }
    return sections;
  }

  Future<FeedResponse?> _fetchOneSource(String sourceId, bool isSerene) {
    // `personalized: true` + `source_id` ⇒ backend route vers le scoring
    // piliers (fenêtre adaptative 24→48→72h), mêmes critères que les sections
    // thème. Flâner appelle sans `personalized` → reste chronologique.
    return _safe<FeedResponse>(
      () => _feedRepo.getFeed(
        page: 1,
        limit: _kThemeSectionPageLimit,
        sourceId: sourceId,
        serein: isSerene,
        personalized: true,
      ),
      'getFeed?source_id=$sourceId&personalized=true',
    );
  }

  /// Construit une section source. Décision PO : **toujours visible** (comme la
  /// veille), même avec 0/1 article — l'état vide est rendu par SectionBlock. On
  /// ne coupe donc jamais sur le seuil `< 2` (contrairement à
  /// [_buildThemeSection]). `null` ne survient pas ici (source déjà résolue).
  FeedThemeSection? _buildSourceSection({
    required FeedResponse? feed,
    required Source source,
  }) {
    final items = feed?.items ?? const <Content>[];
    final hasMore = _themeHasMore(
      feed?.pagination.hasNext ?? false,
      items.length,
    );
    return FeedThemeSection(
      kind: SectionKind.source,
      label: source.name,
      accent: sourceAccentFor(source.id),
      coreVisibleCount: 3,
      sourceId: source.id,
      sourceLogoUrl: source.logoUrl,
      items: items,
      hasMore: hasMore,
    );
  }

  Map<String, FluxSection> _tourneeSectionByKey() {
    // Story Essentiel UX — modèle exclusif thèmes : un thème dont la clé
    // `theme:<slug>` figure dans `pinned_tabs_order_v1` est livré en **onglet
    // Flâner** et donc exclu des sections Essentiel (miroir des sources). Un
    // seul point de filtre suffit : `_orderedTourneeKeys` se base sur
    // `sectionByKey.containsKey(key)`, donc ces thèmes disparaissent aussi de
    // l'ordre Essentiel.
    final flanerThemeKeys = <String>{
      for (final key in ref.read(tabOrderPrefsProvider))
        if (key.startsWith('theme:')) key,
    };
    return {
      if (_actusDuJour != null) kTourneeActusKey: _actusDuJour!,
      if (_bonnes != null) kTourneeBonnesKey: _bonnes!,
      for (final section in _themes)
        if (!flanerThemeKeys.contains(sectionKey(section)))
          sectionKey(section): section,
      for (final section in _sources) sectionKey(section): section,
    };
  }

  /// Liste ordonnée des clés sous "L'Essentiel du jour" : éditorial, Grille,
  /// thèmes, sources et veille partagent le même cap d'affichage.
  List<String> _orderedTourneeKeys({
    required bool isSerene,
    required bool customized,
    required Map<String, FluxSection> sectionByKey,
    required bool grilleAvailable,
    required Set<String> hiddenKeys,
    required List<String> order,
  }) {
    final themeKeys = [
      for (final section in _themes)
        if (section.kind == SectionKind.theme) sectionKey(section),
    ];
    final sourceKeys = [for (final section in _sources) sectionKey(section)];
    final veilleKeys = [
      for (final section in _themes)
        if (section.kind == SectionKind.veille) sectionKey(section),
    ];
    final favoriteKeys = [...themeKeys, ...sourceKeys, ...veilleKeys];
    final useSereneDefault = isSerene && !customized;
    final defaultKeys = useSereneDefault
        ? <String>[
            kTourneeBonnesKey,
            ...favoriteKeys,
            kTourneeActusKey,
            if (grilleAvailable) kTourneeGrilleKey,
          ]
        : <String>[
            kTourneeActusKey,
            if (grilleAvailable) kTourneeGrilleKey,
            ...favoriteKeys,
            kTourneeBonnesKey,
          ];
    final availableKeys = [
      for (final key in defaultKeys)
        if (!hiddenKeys.contains(key) &&
            (key == kTourneeGrilleKey || sectionByKey.containsKey(key)))
          key,
    ];
    return applyOrder(
      availableKeys,
      order,
      (key) => key,
    ).take(kTourneeVisibleCap).toList(growable: false);
  }

  int? _resolveGrilleSlotIndex({
    required List<String> orderedKeys,
    required List<FluxSection> finalSections,
  }) {
    final grilleIndex = orderedKeys.indexOf(kTourneeGrilleKey);
    if (grilleIndex < 0) return null;
    final keysBeforeGrille = <String>{
      if (_essentiel != null) sectionKey(_essentiel!),
      ...orderedKeys.take(grilleIndex).where((key) => key != kTourneeGrilleKey),
    };
    var slot = 0;
    for (final section in finalSections) {
      if (keysBeforeGrille.contains(sectionKey(section))) slot++;
    }
    // `slot` counts the surviving sections that precede the Grille, so it is
    // always within `[0, finalSections.length]` — no clamping needed.
    return slot;
  }

  String _customTopicLabel(UserInterestsState? interests, String id) {
    final found = interests?.customTopics.where((t) => t.id == id).firstOrNull;
    return found?.topicName ?? 'Sujet personnalisé';
  }

  Color _customTopicAccent(UserInterestsState? interests, String id) {
    final found = interests?.customTopics.where((t) => t.id == id).firstOrNull;
    if (found != null) {
      return visualFor(found.slugParent).accent;
    }
    return visualFor('').accent;
  }

  /// Replays only the theme-section fetches against the new favorite list.
  /// Saves the cost of refetching the digest, which doesn't depend on
  /// favorites.
  Future<void> _refetchThemesOnly(List<FavoriteRef> nextFavorites) async {
    final isSerene = ref.read(sereinToggleProvider).enabled;
    final picked = _pickExplicitFavorites(nextFavorites);
    final themes = await _fetchThemeSections(picked, isSerene);
    _lastFavorites = picked;
    _themes = themes;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(_compose(isSerene));
  }

  bool _favoriteListsEqual(List<FavoriteRef> a, List<FavoriteRef> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  /// Replays only the source-section fetches against the new favorite-source
  /// list. Le digest et les thèmes ne dépendent pas des sources favorites.
  Future<void> _refetchSourcesOnly(List<SourceFavoriteRef> picked) async {
    final isSerene = ref.read(sereinToggleProvider).enabled;
    _sources = await _fetchSourceSections(picked, isSerene);
    _lastSourceFavorites = picked;
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(_compose(isSerene));
  }

  /// `SourceFavoriteRef.==` ne compare que `sourceId` ; on compare aussi la
  /// `position` car l'ordre des sections en dépend (tri dans
  /// [_pickFavoriteSources]).
  bool _sourceFavoritesEqual(
    List<SourceFavoriteRef> a,
    List<SourceFavoriteRef> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].sourceId != b[i].sourceId || a[i].position != b[i].position) {
        return false;
      }
    }
    return true;
  }

  Future<T?> _safe<T>(
    Future<T?> Function() fn,
    String label, {
    T? fallback,
  }) async {
    try {
      return await fn();
    } catch (e) {
      debugPrint('FluxContinu: $label failed: $e');
      return fallback;
    }
  }
}
