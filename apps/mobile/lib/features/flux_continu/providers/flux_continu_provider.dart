import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart' show authStateProvider;
import '../../../core/providers/analytics_provider.dart'
    show analyticsServiceProvider;
import '../../alerts/models/alert_item.dart';
import '../../alerts/providers/alerts_provider.dart' show alertsProvider;
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
import '../../settings/providers/display_mode_provider.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../../sources/models/source_model.dart';
import '../../sources/models/theme_source_model.dart' show FollowedTheme;
import '../../sources/providers/sources_providers.dart'
    show userSourcesProvider, themesFollowedProvider;
import '../../veille/providers/veille_active_config_provider.dart';
import '../models/flux_continu_models.dart';
import '../repositories/essentiel_repository.dart';
import '../repositories/flux_continu_repository.dart';
import '../services/flux_continu_cache_service.dart';
import '../services/tournee_progress_service.dart';
import 'essentiel_placement_sync.dart' show reconcileEssentielPlacement;
import '../utils/notif_teasers.dart';
import '../utils/section_fit.dart';
import '../utils/section_score_order.dart';
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

/// Plancher de topics pour « Actus du jour » (DigestTopicSection kind=essentiel).
/// Sans plancher, un digest pauvre (compte neuf / onboarding) n'expose qu'un
/// seul topic → une carte isolée perçue comme un « Essentiel à 1 article ». On
/// masque la section sous ce seuil, à l'image du garde 202 de la carte hi-fi.
/// Bonnes Nouvelles (kind=bonnes) conserve un plancher de 1 (peut légitimement
/// être courte hors mode serein).
const int _kActusMinTopics = 2;

/// Hard cap on the number of favorite theme sections rendered in the tournée.
/// **Source de vérité unique** = [kTourneeVisibleCap] (cap d'affichage global de
/// la Tournée) : il ne doit jamais plafonner les thèmes **sous** ce cap, sinon un
/// mix thèmes+sources serait silencieusement tronqué avant même le cap
/// d'affichage. Aliasé (pas dupliqué) pour rester synchronisé par construction.
const int _kMaxFavoriteSections = kTourneeVisibleCap;

/// Hard cap on the number of favorite SOURCE sections rendered in the tournée
/// (PR « Sources dans la Tournée »). Parité avec les thèmes ([kTourneeVisibleCap]).
const int _kMaxFavoriteSourceSections = kTourneeVisibleCap;

/// Number of items requested per page for each theme section of the Tournée
/// (initial load + each "loadMoreTheme" call).
///
/// Maintenu à 10 (décision PO) : le cold-open tire déjà un appel
/// `personalized=true` **par section** sur un unique worker uvicorn, doubler la
/// page doublerait cette charge. Le volume est repris côté lazy loading
/// ([_themeHasMore] + top-up de la page dédiée) plutôt que par une page plus
/// grosse.
///
/// Story 22.8 — ce budget a grossi : `kFavoriteCap` 7 → 10 (thèmes et sources
/// comptés séparément) porte le pire cas d'environ 19 à environ 25 appels, soit
/// ~2 tours de plus à [_kPhase2FanoutConcurrency]. Non mesuré dans ce lot ;
/// c'est le premier endroit à regarder si le temps d'ouverture régresse.
const int kThemeSectionPageLimit = 10;

/// Borne de concurrence du fan-out Phase 2 (cold-open). Le backend tourne sous
/// un **unique worker uvicorn** et le scoring perso est CPU-bound : tirer les
/// ~10 appels `personalized=true` d'un coup les sérialise côté serveur et fait
/// blinder le wall-clock d'ouverture sur la section la plus lente (timeout 8s
/// ⇒ +10s ressentis). On en garde au plus 3 en vol, dans l'ordre de rendu, en
/// émettant l'état au fur et à mesure (cf. [_fanOutSectionsProgressive]).
const int _kPhase2FanoutConcurrency = 3;

/// Attente maximale du catalogue `userSourcesProvider` quand des sections
/// source doivent être rendues (cf. [FluxContinuNotifier._ensureSourceCatalog]).
/// Court : au-delà on rend la Tournée sans elles plutôt que de la retarder.
const Duration _kSourceCatalogWait = Duration(seconds: 2);

/// B1 — tête d'avance accordée à `/api/essentiel` (vague 1, seul sur le réseau)
/// avant le départ de la vague 2 (digest/both + top-thèmes + kick des providers
/// de coquilles). La vague 2 part à `min(essentiel résolu, ce délai)` : borné,
/// un essentiel pendu ne retarde jamais la Phase 1 de plus de 600 ms.
const Duration _kHeroHeadStart = Duration(milliseconds: 600);

/// Usable scroll height (px) of the Flux Continu viewport, threaded from
/// [FluxContinuScreen] (the only place that can measure it post-layout):
/// ```
/// usableViewportHeight = scrollViewportHeight − safeAreaBottom − kStickyBarHeight
/// ```
/// — the **exact same budget** the section snap uses to decide whether a
/// section is "tall". `null` on the first frame (no measure yet) ⇒ the provider
/// keeps the default visible counts and recomposes once the measure lands
/// (masked by the loading skeleton). The screen writes it only when the rounded
/// value changes (anti-boucle). Consumed by [FluxContinuNotifier._compose] to
/// trim the hero and cap each downstream section so no card stack ever exceeds
/// the screen. The footer auto-hide does **not** change this budget (the snap
/// already subtracts only `safeAreaBottom`, not the footer height).
final usableViewportHeightProvider = StateProvider<double?>((ref) => null);

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
  // Story 32.1 — carrousel semi-éditorialisé du jour servi par `/api/essentiel`
  // (`carousel`), mutualisé avec Flâner. `null` hors édition du jour ou si aucun
  // type n'est éligible. Inséré hors-cap en fin de `_compose` (comme les
  // alertes). Non caché (surface additive, live, today-only).
  FeedCarouselData? _essentielCarousel;
  // Up to [_kMaxFavoriteSections] theme/topic sections, ordered to mirror
  // `userInterestsProvider.favorites`. Empty when the user has no favorites
  // — the tournée then collapses to digest only.
  List<FeedThemeSection> _themes = const [];
  // Up to [_kMaxFavoriteSourceSections] source sections (PR « Sources dans la
  // Tournée »), résolues depuis `userSourcesStateProvider.favorites` +
  // catalogue `userSourcesProvider`. Composées entre les thèmes et la veille.
  List<FeedThemeSection> _sources = const [];
  // Story 22.3 — sections « Choisie pour vous » (suggérées), résolues depuis le
  // payload `getTopThemes` (`origin=="suggested"`), best-first par daily_rank.
  // Remplissent les slots restants APRÈS les validées ; jamais une validée.
  List<FeedThemeSection> _suggested = const [];
  // Dernières sources favorites (sourceId+position) rendues — sert au listener
  // `userSourcesStateProvider` pour ne refetch que sur un vrai changement.
  List<SourceFavoriteRef> _lastSourceFavorites = const [];
  bool _closingDismissed = false;
  // Citation du jour servie par le backend (sérène ou normal — même pool
  // YAML, sélection déterministe seed = user_id + date). Rendue avant
  // ClosingCardV18 comme clôture éditoriale de la tournée.
  QuoteResponse? _quote;
  final Set<String> _dismissedIds = <String>{};

  bool _closingPersistQueued = false;
  bool _essentielViewedMarked = false;

  /// `sectionKey` des sections dont le fetch du fan-out a **résolu** ce cycle
  /// (réponse arrivée, vide ou non) — favorites comme suggérées.
  /// [_classifyFavoriteSections] et [_dropStarvedSections] n'inspectent que ces
  /// clés : une coquille seedée non encore résolue (0 item au boot) ne doit pas
  /// être jugée en pénurie → elle serait masquée puis rendue à l'arrivée de sa
  /// réponse, soit un clignotement à chaque recomposition du fan-out.
  /// Réinitialisé au reseed complet ([_buildStateFromPayload]), augmenté au fil
  /// du fan-out et des refetch partiels.
  final Set<String> _resolvedSectionKeys = <String>{};

  /// PR-4 — ordre des blocs par score **gelé pour la journée tournée**
  /// ([_scoreOrderDayKey], frontière 07h30 Paris), lu **sync** par [_compose]
  /// sur le modèle de `_closingDismissed`.
  ///
  /// Pourquoi geler : `_fanOutSectionsProgressive` émet après chaque tâche
  /// (~10-15 recompositions) ; trier à chaque emit ferait sauter les blocs sous
  /// les yeux de l'utilisateur. `null` ⇒ ordre par défaut. Il est calculé
  /// **une seule fois**, à la complétion du fan-out, puis rejoué tel quel par
  /// tous les composes suivants du jour (cache in-day, pull-to-refresh, refetch
  /// partiels, load-more).
  String? _scoreOrderDayKey;
  List<String>? _scoreOrderKeys;

  /// Blocs favoris jugés **pauvres** (curation du jour), gelés au même instant
  /// et depuis les mêmes scores que [_scoreOrderKeys] — donc stables toute la
  /// journée et cohérents avec l'ordre. Sans ce gel, un « Voir +10 » sur un bloc
  /// déclassé le ferait remonter sous les doigts de l'utilisateur.
  Set<String> _poorBlockKeys = const {};

  /// Armé à la complétion du fan-out, consommé par le [_compose] qui suit
  /// immédiatement : c'est lui qui gèle l'ordre, à partir des scores qu'il a
  /// déjà en main (cf. [_freezeScoreOrder]).
  bool _freezeScoreOrderOnNextCompose = false;

  /// True du tout début de [build] jusqu'à la fin du 1er [_fetchAll]. Pendant
  /// cette fenêtre, l'état affiché peut être un **squelette** (sections vides) :
  /// les listeners de prefs ne doivent donc ni recomposer (le dédup viderait les
  /// sections éditoriales vides) ni refetch (tempête de 401 prématurée). Le 1er
  /// `_fetchAll` lit de toute façon les prefs les plus fraîches, donc tout
  /// changement survenu pendant le bootstrap est capturé sans listener. Restaure
  /// l'invariant « aucune réaction de listener avant le 1er build complet » que
  /// l'ancien chemin cold tenait implicitement (state sans valeur).
  bool _bootstrapping = false;

  /// True entre la disposition du provider et un éventuel rebuild. Riverpod 2
  /// n'expose pas `ref.mounted` : ce drapeau (posé par `ref.onDispose`) garde
  /// les continuations **asynchrones** lancées depuis [build] (cf.
  /// [_reconcilePlacementThenSync]) de toucher `ref`/`state` après coup.
  bool _disposed = false;

  /// Snapshot of the favorite order we last fetched for. Used by the
  /// userInterestsProvider listener to detect changes and refetch only the
  /// theme sections (cheap) instead of the full tournée.
  List<FavoriteRef> _lastFavorites = const [];

  /// Chronomètre du bootstrap pour la grammaire `[PERF]` : armé à l'entrée de
  /// [build], relâché dans son `finally` — toutes les métriques du boot
  /// (`gate_ms` → `fanout_done_ms`) partagent donc la même origine. `null` hors
  /// bootstrap ⇒ les chemins refresh / refetch partiels ne loggent rien.
  Stopwatch? _bootSw;

  /// Ligne `[PERF] fluxContinu.<metric>=<ms depuis l'entrée de build>[suffix]`.
  /// No-op hors bootstrap (cf. [_bootSw]).
  void _perfBoot(String metric, [String suffix = '']) {
    final sw = _bootSw;
    if (sw == null) return;
    debugPrint('[PERF] fluxContinu.$metric=${sw.elapsedMilliseconds}$suffix');
  }

  @override
  Future<FluxContinuState> build() async {
    _bootstrapping = true;
    _bootSw = Stopwatch()..start();
    _disposed = false;
    // B2 — les listeners différés d'un build précédent ont été fermés par le
    // rebuild : on ré-arme l'enregistrement (cf. [_kickDeferredBootProviders]).
    _deferredListenersRegistered = false;
    ref.onDispose(() => _disposed = true);
    _digestRepo = ref.read(digestRepositoryProvider);
    _feedRepo = ref.read(feedRepositoryProvider);
    _fluxRepo = ref.read(fluxContinuRepositoryProvider);
    _essentielRepo = ref.read(essentielRepositoryProvider);
    _cacheService = FluxContinuCacheService();

    ref.listen<SereinToggleState>(sereinToggleProvider, (prev, next) {
      if (_bootstrapping) return;
      if (prev?.enabled != next.enabled && state.hasValue) {
        // Vide le cache de la vue feed par défaut (Flâner) pour que la vue
        // visible re-fetche avec le bon paramètre `serein` au lieu de servir le
        // résultat dédupliqué de l'autre mode. Le snapshot Flux du mode
        // précédent est lui ignoré au prochain `build` (mode mismatch), donc
        // on ne réaffiche jamais l'ancien contenu : squelette → refetch complet.
        FeedRepository.clearDefaultViewCache();
        ref.invalidateSelf();
      }
    });

    // La hauteur utile mesurée par l'écran pilote le « combien d'articles
    // tiennent » (trim héros + cap des sections aval). On recompose à chaque
    // changement, comme pour le toggle sérène — un simple recompose suffit, les
    // sections sont déjà fetchées (on ne refait que le découpage d'affichage).
    ref.listen<double?>(usableViewportHeightProvider, (prev, next) {
      if (_bootstrapping) return;
      if (prev == next) return;
      if (!state.hasValue) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    // Changement de mode d'affichage (Normal / Minimaliste / Ludique) : les
    // hauteurs de cartes du budget fit changent → simple recompose, comme pour
    // la hauteur utile (les sections sont déjà fetchées).
    ref.listen<DisplayMode>(displayModeNotifierProvider, (prev, next) {
      if (_bootstrapping) return;
      if (prev == next) return;
      if (!state.hasValue) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    // Story 10.2 — `tournee_order_v1` fait autorité pour le **mode** des sources :
    // une source y figure ⇒ mode « Essentiel ». Deux cas à distinguer ici :
    //  - l'ensemble des clés `source:` de l'ordre change (une source entre ou
    //    sort de l'Essentiel) ⇒ il faut **refetch** : une source qui entre
    //    n'existe pas encore dans `_sources` ; une qui sort doit en disparaître.
    //  - sinon (réordre/masques) ⇒ simple recompose (sections déjà fetchées).
    ref.listen<TourneeOrderState>(tourneeOrderPrefsProvider, (prev, next) {
      if (_bootstrapping) return;
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
      if (_bootstrapping) return;
      if (!state.hasValue) return;
      if (setEquals(_themeKeysOf(prev), _themeKeysOf(next))) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    final isSerene = ref.read(sereinToggleProvider).enabled;

    // Première peinture : on lit le snapshot SANS le jeter sur un day mismatch.
    // On exige aussi que le snapshot ait été écrit dans le **même mode serein**
    // que le mode courant — sinon (toggle serein → invalidateSelf) son contenu
    // mode-dépendant (Essentiel, sections feed) est périmé : on tombe alors sur
    // le squelette + refetch complet plutôt que de réafficher l'ancien snapshot.
    final snapshot = await _cacheService.readLatest();
    final snapshotUsable = snapshot != null &&
        !snapshot.isStale &&
        snapshot.sereinEnabled == isSerene;
    if (snapshotUsable) {
      // Snapshot du jour → SWR in-day : on peint le **vrai** contenu
      // instantanément (puis revalidation via _fetchAll).
      debugPrint('[PERF] fluxContinu.build mode=content_fresh');
      state = AsyncData(
        await _buildStateFromPayload(
          dual: snapshot.dual,
          topThemes: snapshot.topThemes,
          essentielArticles: snapshot.essentielArticles,
          isSerene: isSerene,
          fetchThemes: false,
        ),
      );
    } else {
      // Snapshot d'hier (stale), mode serein différent, ou aucun → on ne peint
      // JAMAIS de contenu périmé : on émet un squelette fidèle dérivé des prefs
      // locales (bon nombre/ordre/labels/accents de sections), rempli derrière.
      debugPrint(
          '[PERF] fluxContinu.build mode=${snapshot == null ? 'cold' : 'skeleton_stale'}');
      state = AsyncData(_buildSkeletonState(isSerene));
    }

    // Garde anti-tempête 401 (stabilité + scalabilité) : on laisse le refresh
    // initial (lancé non-bloquant par AuthStateNotifier) se résoudre — borné par
    // un timeout court — AVANT de tirer les ~3+14 appels, pour qu'ils partent
    // avec un JWT frais. Le squelette/cache est déjà peint, donc cette attente
    // gate la DATA, pas les pixels.
    await _awaitInitialRefresh();
    _perfBoot('gate_ms');

    // B1/B2 — chemin warm (vrai contenu déjà peint depuis le snapshot) : rien
    // ne concurrence le héros, on arme tout de suite la vague 3 (listeners
    // réseau différés + réconciliation de placement), post-gate donc JWT frais.
    // Sur le chemin froid, elle n'est armée qu'après l'émission de la Phase 1
    // (cf. [_buildStateFromPayload]).
    if (snapshotUsable) {
      _kickDeferredBootProviders();
    }

    try {
      return await _fetchAll();
    } finally {
      _bootstrapping = false;
      _bootSw = null;
      // Filet de sécurité (chemin d'erreur / Phase 1 jamais émise) : les
      // listeners réseau doivent TOUJOURS finir enregistrés — sans eux, plus
      // aucune réaction aux favoris/grille/alertes jusqu'au prochain build.
      // No-op dans le cas nominal (déjà armés à la Phase 1 ou au chemin warm).
      _kickDeferredBootProviders();
    }
  }

  /// Attend le refresh initial en cours (cf. `AuthStateNotifier.initialRefresh`)
  /// borné par un timeout court. Tout échec (timeout, AuthException, ou notifier
  /// auth indisponible en test) est avalé : on tombe alors dans [_fetchAll] où
  /// l'intercepteur 401 single-flight (`api_client`) reste le filet de sécurité.
  Future<void> _awaitInitialRefresh() async {
    try {
      final refresh = ref.read(authStateProvider.notifier).initialRefresh;
      if (refresh == null) return;
      await refresh.timeout(const Duration(seconds: 3));
    } catch (_) {
      // Refresh raté/expiré ou auth indisponible (tests) — le filet 401 prend
      // le relais ; AuthStateNotifier gère lui-même le chemin signout sur un
      // refresh token mort.
    }
  }

  /// B2 — vague 3 armée (listeners réseau + réconciliation). Ré-armé à chaque
  /// [build] : un rebuild ferme les subscriptions du build précédent.
  bool _deferredListenersRegistered = false;

  /// B2 vague 3 — enregistre les `ref.listen` **réseau** différés (favoris
  /// thème/sujet, favoris source, grille, thèmes suivis, alertes) et lance la
  /// réconciliation de placement Essentiel/Flâner.
  ///
  /// Pourquoi différé : `ref.listen` **initialise** le provider écouté — posés
  /// en tête de [build] comme avant, ces 5 listens faisaient partir leurs
  /// fetchs en concurrence directe de `/api/essentiel` sur le pool Dio et
  /// l'unique worker uvicorn (D2). Un `ref.listen` tardif (post-await dans
  /// build) est légal en Riverpod 2.6 ; pendant la fenêtre restante de
  /// bootstrap, leurs corps restent muets (`_bootstrapping`), comme avant.
  ///
  /// Appelé (le flag rend l'appel idempotent) :
  ///  - chemin froid : juste après l'émission de la Phase 1 ;
  ///  - chemin warm : juste après le gate JWT (le snapshot est déjà peint) ;
  ///  - filet : dans le `finally` de [build] (chemin d'erreur).
  void _kickDeferredBootProviders() {
    if (_disposed || _deferredListenersRegistered) return;
    _deferredListenersRegistered = true;

    // React to favorite reorders / additions / removals without rebuilding
    // the digest (the digest doesn't depend on favorites).
    ref.listen<AsyncValue<UserInterestsState>>(userInterestsProvider, (
      prev,
      next,
    ) {
      if (_bootstrapping) return;
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
      if (_bootstrapping) return;
      final nextFavorites = next.valueOrNull?.favorites;
      if (nextFavorites == null) return;
      final picked = _pickFavoriteSources(nextFavorites);
      if (_sourceFavoritesEqual(_lastSourceFavorites, picked)) return;
      if (!state.hasValue) return;
      unawaited(_refetchSourcesOnly(picked));
    });

    // La Grille est un slot autonome dans la liste cappée : sa présence dépend
    // uniquement de `today != null`, pas des sections déjà fetchées.
    ref.listen<AsyncValue<GrilleState>>(grilleProvider, (prev, next) {
      if (_bootstrapping) return;
      if (!state.hasValue) return;
      final wasPresent = prev?.valueOrNull?.today != null;
      final isPresent = next.valueOrNull?.today != null;
      if (wasPresent == isPresent) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    // Story 22.5 — `themesFollowedProvider` est lazy : ce listen le déclenche
    // (désormais en vague 3, plus en tête de build) et recompose à sa
    // résolution (et à tout changement du count après follow/unfollow) pour
    // re-stamper `followedSourceCount` ([_stampFollowedCounts]) → le CTA
    // « Tout lire »/« Ajouter » se corrige sans attendre un refetch complet.
    ref.listen<AsyncValue<List<FollowedTheme>>>(themesFollowedProvider, (
      prev,
      next,
    ) {
      if (_bootstrapping) return;
      if (!state.hasValue) return;
      if (next.valueOrNull == null) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    // `alertsProvider` est lazy comme `themesFollowedProvider` : ce listen le
    // déclenche (vague 3) et recompose à sa résolution (et à chaque
    // pose/retrait de cloche) — sinon le rappel « Tes alertes » n'apparaîtrait
    // qu'au prochain refetch complet de la Tournée.
    ref.listen<AsyncValue<AlertsState>>(alertsProvider, (prev, next) {
      if (_bootstrapping) return;
      if (!state.hasValue) return;
      if (next.valueOrNull == null) return;
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    });

    // Réconciliation du placement Essentiel/Flâner (source de vérité DB) —
    // non-bloquante : elle ne doit pas retarder la DATA (l'awaiter ajouterait
    // 2 RTT à tous les cold boots). Déplacée de l'avant-`_fetchAll` vers la
    // vague 3 : ses 2 GETs ne concurrencent plus le héros ni la Phase 1. Son
    // résultat est chaîné explicitement, sans dépendre des listeners prefs
    // (cf. [_reconcilePlacementThenSync]).
    unawaited(_reconcilePlacementThenSync());
  }

  /// B2 — valeur résolue de [provider], **sans l'initialiser pendant le
  /// bootstrap** : les sites de composition squelette/compose lisaient ces
  /// providers lazy via `ref.read`, ce qui les initialisait « en douce » et
  /// faisait partir leurs fetchs en concurrence de `/api/essentiel` (D2).
  /// La suppression est bornée à la fenêtre de bootstrap : hors bootstrap,
  /// `ref.read` normal (sémantique historique — un futur appelant pré-vague 3
  /// ne dégraderait pas en silence). Pendant le bootstrap, un provider pas
  /// encore vivant rend `null` — dégrade exactement comme le cold start
  /// historique (valeur absente).
  T? _peekValue<T>(ProviderBase<AsyncValue<T>> provider) {
    if (!_bootstrapping) return ref.read(provider).valueOrNull;
    return ref.exists(provider) ? ref.read(provider).valueOrNull : null;
  }

  /// B1 vague 2 — force l'init des providers dont dépend le **seed des
  /// coquilles** de la Tournée (favoris thème/sujet, favoris source, catalogue
  /// source, config veille). Lancés après l'avance du héros : leurs fetchs
  /// voyagent pendant que digest/top-thèmes sont en vol.
  void _kickShellPrereqs() {
    ref.read(userInterestsProvider);
    ref.read(userSourcesStateProvider);
    ref.read(userSourcesProvider);
    ref.read(veilleActiveConfigProvider);
  }

  /// Attente **bornée** (miroir de [_kSourceCatalogWait]) de la résolution des
  /// providers seedant les coquilles, avant [_pickFavorites] /
  /// [_pickFavoriteSources]. Corrige au passage la course silencieuse
  /// historique : `_pickFavorites` lisait un provider pas encore résolu et
  /// seedait 0 coquille pour tout le cycle. Erreurs/timeout avalés : on seede
  /// alors en dégradé, comme avant.
  Future<void> _awaitShellPrereqs() async {
    // Erreurs avalées **par future** : un prérequis en échec rapide (ex. veille
    // 404) ne doit pas court-circuiter l'attente des deux autres.
    try {
      await Future.wait<void>([
        ref.read(userInterestsProvider.future),
        ref.read(userSourcesStateProvider.future),
        ref.read(veilleActiveConfigProvider.future),
      ].map((f) => f.then<void>((_) {}, onError: (_) {})))
          .timeout(_kSourceCatalogWait);
    } catch (e) {
      debugPrint('FluxContinu: shell prereqs unresolved: $e');
    }
  }

  /// Lance [reconcileEssentielPlacement] et **applique son résultat au rendu**,
  /// sans dépendre des listeners de prefs.
  ///
  /// Bug « Sources favorites absentes » (race 1) : la réconciliation (2 GETs)
  /// se résout presque toujours *pendant* le fan-out, donc pendant que
  /// `_bootstrapping` est encore vrai — or les listeners `tournee_order` /
  /// `pinned_tabs` sont muets dans cette fenêtre. L'hydratation DB → prefs qui
  /// **restaure** l'appartenance Essentiel d'une source (réinstall / nouveau
  /// device) était donc avalée : la section n'apparaissait qu'au cold boot
  /// suivant. On compare ici l'avant/après nous-mêmes.
  ///
  /// Idempotent vis-à-vis des listeners : si la réconciliation se résout après
  /// le bootstrap, le listener a déjà lancé le refetch (et posé
  /// `_lastSourceFavorites`) ⇒ la comparaison ci-dessous est un no-op.
  Future<void> _reconcilePlacementThenSync() async {
    final themeKeysBefore = _themeKeysOf(ref.read(tabOrderPrefsProvider));
    await reconcileEssentielPlacement(ref);
    if (_disposed || !state.hasValue) return;
    // Sources : une source restaurée en mode « Essentiel » n'a ni section ni
    // clé d'ordre ⇒ un recompose ne suffit pas, il faut la fetcher. Le cas ne
    // se produit que sur un vrai drift (one-shot par device), donc le
    // chevauchement avec le fan-out en cours reste marginal.
    final picked = _pickFavoriteSources();
    if (!_sourceFavoritesEqual(_lastSourceFavorites, picked)) {
      await _refetchSourcesOnly(picked);
      return;
    }
    // Thèmes : leurs sections sont déjà fetchées (les favoris thème ne
    // dépendent pas de `pinned_tabs_order_v1`) — seule leur **appartenance** à
    // la Tournée change ⇒ recompose.
    if (!setEquals(themeKeysBefore, _themeKeysOf(ref.read(tabOrderPrefsProvider)))) {
      state = AsyncData(_compose(ref.read(sereinToggleProvider).enabled));
    }
  }

  /// Sous-ensemble des clés `theme:` d'un ordre d'onglets Flâner
  /// (`pinned_tabs_order_v1`) — l'appartenance des thèmes à la Tournée. Partagé
  /// par le listener `tabOrderPrefsProvider` et [_reconcilePlacementThenSync]
  /// (fenêtre de bootstrap où ce listener est muet) pour que la règle de
  /// filtrage reste définie une seule fois.
  static Set<String> _themeKeysOf(List<String>? keys) => {
        for (final k in keys ?? const <String>[])
          if (k.startsWith('theme:')) k,
      };

  Future<FluxContinuState> _fetchAll() async {
    final isSerene = ref.read(sereinToggleProvider).enabled;

    // B1 vague 1 — le « paquet prioritaire » `/api/essentiel` part SEUL : rien
    // d'autre ne le concurrence sur le pool Dio ni sur l'unique worker uvicorn.
    final essentielFuture = _safe<EssentielFetchResult>(
      // Passe le mode explicitement : `isSerene` est posé en synchrone avant
      // l'`invalidateSelf` du listener serein, donc à jour ici — pas de
      // dépendance à la persistance DB de la préférence au moment du refetch.
      () async =>
          (await _essentielRepo.fetch(serein: isSerene)) ??
          (
            articles: const <EssentielArticle>[],
            newSinceMorning: 0,
            carousel: null,
          ),
      'fetchEssentiel',
      fallback: (
        articles: const <EssentielArticle>[],
        newSinceMorning: 0,
        carousel: null,
      ),
    );
    _perfBoot('essentiel_dispatch_ms');

    // Le héros ne dépend QUE de `/api/essentiel`, mais attendait jusqu'ici le
    // `Future.wait` complet — donc la plus lente des trois, en pratique
    // `/api/digest/both` (deux digests rendus, chacun portant le texte intégral
    // des articles). On peint donc la pile dès que l'Essentiel atterrit, sans
    // attendre le digest : c'est le premier contenu réel que l'utilisateur voit.
    //
    // L'émission reste un **squelette** (`_composeSkeleton`, `isSkeleton: true`)
    // : seul le héros s'hydrate, les sections aval gardent leurs placeholders.
    // C'est ce qui préserve les invariants existants — `emitProgressive`
    // (plus bas) teste `mounted.isSkeleton` pour décider d'émettre la Phase 1,
    // et un état non-squelette ici l'aurait désarmé, figeant la page haute.
    unawaited(
      essentielFuture.then((early) {
        _perfBoot('essentiel_resolved_ms');
        if (_disposed || early == null || early.articles.isEmpty) return;
        if (!(state.valueOrNull?.isSkeleton ?? false)) return;
        _essentielCarousel = early.carousel;
        _essentiel = _buildEssentielSection(
          early.articles,
          newSinceMorning: early.newSinceMorning,
        );
        state = AsyncData(_composeSkeleton(isSerene));
        _perfBoot('hero_emit_ms');
      }),
    );

    // B1 vague 2 — gatée sur min(essentiel résolu, [_kHeroHeadStart]) : le
    // héros garde une tête d'avance, mais un essentiel pendu ne coûte jamais
    // plus de 600 ms au reste de la Phase 1 (le gate est borné, pas otage du
    // timeout 8 s de l'essentiel). La tête d'avance ne protège qu'un héros
    // **pas encore peint** : hors squelette monté (revalidation SWR in-day,
    // pull-to-refresh — l'early-emit ci-dessus y est un no-op), elle ne serait
    // que du délai mort chargé au spinner → la vague 2 part immédiatement.
    if (state.valueOrNull?.isSkeleton ?? true) {
      await Future.any<Object?>([
        essentielFuture,
        Future<void>.delayed(_kHeroHeadStart),
      ]);
    }
    final digestFuture = _safe<DualDigestResponse>(
      () => _digestRepo.fetchBothDigests(),
      'fetchBothDigests',
    );
    final topThemesFuture = _safe<List<TopTheme>>(
      () => _fluxRepo.getTopThemes(),
      'getTopThemes',
      fallback: const <TopTheme>[],
    );
    // Prérequis du seed des coquilles : leurs fetchs voyagent pendant que
    // digest/top-thèmes sont en vol (attente bornée dans
    // [_buildStateFromPayload] via [_awaitShellPrereqs]).
    _kickShellPrereqs();

    final results = await Future.wait([
      digestFuture,
      topThemesFuture,
      essentielFuture,
    ]);
    final dual = results[0] as DualDigestResponse?;
    final topThemes = (results[1] as List<TopTheme>?) ?? const <TopTheme>[];
    final essentielResult = results[2] as EssentielFetchResult?;
    final essentielArticles =
        essentielResult?.articles ?? const <EssentielArticle>[];
    final newSinceMorning = essentielResult?.newSinceMorning ?? 0;

    final next = await _buildStateFromPayload(
      dual: dual,
      topThemes: topThemes,
      essentielArticles: essentielArticles,
      isSerene: isSerene,
      fetchThemes: true,
      newSinceMorning: newSinceMorning,
      essentielCarousel: essentielResult?.carousel,
    );
    if (dual != null) {
      unawaited(
        _cacheService.write(
          dual: dual,
          topThemes: topThemes,
          essentielArticles: essentielArticles,
          sereinEnabled: isSerene,
        ),
      );
      // Rafraîchit uniquement les teasers locaux Bonnes Nouvelles. Les teasers
      // Essentiel viennent désormais du push serveur basé sur le digest exact.
      unawaited(_syncNotificationTeasers(dual, essentielArticles));
    }
    return next;
  }

  /// Pousse les teasers Bonnes Nouvelles vers les réglages. Non bloquant :
  /// une erreur de scheduling ne doit jamais casser le rendu du home.
  Future<void> _syncNotificationTeasers(
    DualDigestResponse dual,
    List<EssentielArticle> essentielArticles,
  ) async {
    try {
      await ref.read(notificationsSettingsProvider.notifier).syncDigestTeasers(
            essentielTeasers: buildEssentielTeasers(essentielArticles),
            goodNewsTeasers: buildGoodNewsTeasers(dual.serein),
            sereinEnabled: dual.sereinEnabled,
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
    int newSinceMorning = 0,
    // Story 32.1 — carrousel du jour (null hors chemin live/aujourd'hui, ex.
    // hydratation depuis cache). Additif : ne change rien quand absent.
    FeedCarouselData? essentielCarousel,
  }) async {
    // Story 32.1 — mémorise le carrousel du jour pour `_compose` (inséré
    // hors-cap en fin de Tournée). Réinitialisé à chaque payload : un refetch
    // sans carrousel (édition passée / plus d'éligible) le retire proprement.
    _essentielCarousel = essentielCarousel;
    // PR2 — la section "Essentiel" du haut du feed est désormais alimentée
    // par GET /api/essentiel (5 articles transversaux). Si l'endpoint n'a
    // rien servi (preparing/erreur), on ne rend pas la section : le digest
    // legacy reste affiché juste en dessous sous le nom "Actus du jour",
    // et Bonnes Nouvelles n'est pas affectée.
    _essentiel = _buildEssentielSection(
      essentielArticles,
      newSinceMorning: newSinceMorning,
    );
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
      minTopics: _kActusMinTopics,
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

    // B1 — chemin réseau uniquement (jamais le chemin cache in-day, qui doit
    // peindre le snapshot sans délai) : attente bornée des providers seedant
    // les coquilles, kickés en vague 2. Dans le cas nominal ils se sont résolus
    // pendant le vol de digest/both → attente ≈ 0 ms.
    if (fetchThemes) {
      await _awaitShellPrereqs();
    }

    final picked = _pickFavorites(topThemes);
    final favorites = picked.refs;
    _lastFavorites = favorites;
    final favoriteSources = _pickFavoriteSources();
    _lastSourceFavorites = favoriteSources;

    // Seed de **coquilles** AVANT le fan-out (fix « Tournée figée » + « thème à
    // 1 carte »). L'ordre de la Tournée (`_orderedTourneeKeys`) est dérivé des
    // sections déjà présentes dans `_themes`/`_sources` : sans seed, une section
    // dont le fan-out (sérialisé sous l'unique worker) n'a pas encore (ou pas)
    // abouti n'a **pas de clé** → elle disparaît de l'ordre, et seuls les blocs
    // éditoriaux restent. En seedant les en-têtes des favoris **résolus** (mêmes
    // label/accent que le rendu réel, items vides), l'ordre reflète **toujours**
    // les préférences ; le fan-out remplace ensuite chaque coquille en place par
    // `sectionKey` (upsert), un fetch raté laissant la coquille (état vide géré
    // par `SectionBlock`) plutôt qu'une section absente. Réservé aux favoris
    // **explicites** : un compte neuf (fallback canonique) garde l'ancien
    // comportement (thèmes pauvres droppés, pas d'empty-state non choisi).
    _themes = picked.isFallback ? const [] : _shellThemeSections(favorites);
    _sources = _shellSourceSections(favoriteSources);
    // Issue #1 — seed des coquilles « Choisie pour vous » AVANT le fan-out
    // (mêmes clés que le rendu réel) : elles sont ordonnées dès la Phase 1 et se
    // remplissent sur place au lieu d'apparaître en net-new (le « pop » ressenti).
    final suggestions = [
      for (final t in topThemes)
        if (t.isSuggested) t
    ];
    _suggested = _shellSuggestedSections(_usableSuggestions(suggestions));
    // Reseed complet ⇒ les coquilles ne sont pas encore résolues : on repart
    // d'une classification vierge (aucune section maigre tant que le fan-out /
    // le chemin cache n'a pas confirmé un contenu réel).
    _resolvedSectionKeys.clear();
    _closingDismissed = await _loadClosingDismissedForToday();
    // PR-4 — avant le chemin cache in-day **comme** avant le fan-out : une
    // ré-ouverture dans la journée rejoue l'ordre trié dès le premier emit
    // (zéro saut), un ordre daté d'hier est ignoré.
    await _loadScoreOrderForToday();
    unawaited(_purgeOldPrefsKeys());
    unawaited(_markEssentielViewedIfNeeded());

    if (!fetchThemes) {
      // Chemin cache in-day : pas de fan-out réseau, on compose directement.
      return _compose(isSerene);
    }

    // Rendu progressif deux-phases. On n'émet l'état base-only intermédiaire que
    // si l'état monté est un squelette (ou absent) — c.-à-d. au démarrage à
    // froid. En SWR in-day / pull-to-refresh, du vrai contenu est déjà monté :
    // on le garde tel quel jusqu'à l'arrivée du set complet (pas de blink des
    // sections thèmes/sources).
    final mounted = state.valueOrNull;
    final emitProgressive = mounted == null || mounted.isSkeleton;

    // Phase 1 — hero/Essentiel/Actus/Bonnes composés (sections thèmes/sources
    // encore vides) : le haut de page réel remplace le squelette après ~1
    // round-trip de base.
    if (emitProgressive) {
      state = AsyncData(_compose(isSerene));
      _perfBoot('phase1_ms');
    }

    // B2 vague 3 — le haut de page réel est émis : on peut maintenant armer
    // les listeners réseau différés + la réconciliation de placement sans
    // concurrencer le héros ni la Phase 1. Idempotent (no-op sur les refetch
    // SWR/pull-to-refresh où la vague 3 est déjà armée).
    _kickDeferredBootProviders();

    // Bug « Sources favorites absentes » (race 2) : le catalogue
    // `userSourcesProvider` est **lazy** — s'il n'est pas encore résolu, chaque
    // favori source est silencieusement droppé du seed ET du fan-out pour tout
    // le cycle. On force sa résolution ici, **après** l'émission Phase 1 pour ne
    // pas retarder le haut de page, puis on re-seed les coquilles source.
    if (await _ensureSourceCatalog(favoriteSources)) {
      _sources = _reseedShells(_sources, _shellSourceSections(favoriteSources));
      if (emitProgressive) {
        state = AsyncData(_compose(isSerene));
      }
    }

    // Phase 2 — fan-out **progressif et borné** des sections thèmes + sources +
    // suggérées « Choisie pour vous ». On part des listes vides (réinitialisées
    // plus haut) et on les remplit au fur et à mesure : le premier rendu n'est
    // plus bloqué sur la section la plus lente (l'ancien `Future.wait` global),
    // et la charge serveur est bornée (1 worker uvicorn → recos perso
    // sérialisées). Réutilise les fetch/build unitaires existants
    // (_fetchOneTheme/_fetchOneSource + builders).
    await _fanOutSectionsProgressive(
      favorites: favorites,
      isExplicitFavorite: !picked.isFallback,
      favoriteSources: favoriteSources,
      suggestions: suggestions,
      isSerene: isSerene,
    );

    return _compose(isSerene);
  }

  /// Construit l'état **squelette** affiché au démarrage matinal (cache d'hier
  /// invalidé) ou à froid : structure de sections fidèle (en-têtes réels —
  /// nombre/ordre/labels/accents dérivés des prefs locales) **sans** contenu.
  /// Les sections sont des coquilles vides (items/topics vides) ; le screen rend
  /// un placeholder par section. Jamais de contenu périmé. Pas de réseau.
  FluxContinuState _buildSkeletonState(bool isSerene) {
    // Coquille « héros pas encore résolu » — **pas** « héros vide » (cf. la
    // convention documentée sur [_buildEssentielSection]). Elle survit à un
    // `_compose()` non-squelette publié pendant le bootstrap ; c'est
    // `EssentielHiFiCard` qui garantit qu'elle se rend en silhouette.
    _essentiel = const EssentielSection(
      articles: <EssentielArticle>[],
      illustrationAsset: _kEssentielIllustration,
      blurb: _kEssentielBlurb,
    );
    _actusDuJour = const DigestTopicSection(
      kind: SectionKind.essentiel,
      label: 'Actus du jour',
      blurb: _kActusDuJourBlurb,
      accent: _kEssentielAccent,
      illustrationAsset: _kEssentielIllustration,
      coreVisibleCount: 3,
      topics: <DigestTopic>[],
    );
    _bonnes = DigestTopicSection(
      kind: SectionKind.bonnes,
      label: 'Bonnes Nouvelles',
      blurb: _kBonnesBlurb,
      accent: _kBonnesAccent,
      illustrationAsset: _kBonnesIllustration,
      coreVisibleCount: isSerene ? 4 : 2,
      topics: const <DigestTopic>[],
    );
    _quote = null;
    _themes = _skeletonThemeSections();
    _sources = _skeletonSourceSections();
    return _composeSkeleton(isSerene);
  }

  /// Ordonne les coquilles de sections du squelette via les mêmes helpers que
  /// [_compose] (`_tourneeSectionByKey` / `_orderedTourneeKeys`) — source unique
  /// de l'ordre — mais SANS dédup/cap/filtre (rien à dédupliquer sur des
  /// sections vides ; le dédup retirerait au contraire les sections éditoriales
  /// vides). Marque `isSkeleton: true`.
  FluxContinuState _composeSkeleton(bool isSerene) {
    final tournee = ref.read(tourneeOrderPrefsProvider);
    final grilleAvailable = _peekValue(grilleProvider)?.today != null;
    final sectionByKey = _tourneeSectionByKey();
    final orderedKeys = _orderedTourneeKeys(
      isSerene: isSerene,
      customized: tournee.customized,
      sectionByKey: sectionByKey,
      grilleAvailable: grilleAvailable,
      hiddenKeys: tournee.hiddenKeys,
      order: tournee.order,
    );
    final sections = <FluxSection>[
      if (_essentiel != null) _essentiel!,
      for (final key in orderedKeys)
        if (key != kTourneeGrilleKey && sectionByKey[key] != null)
          sectionByKey[key]!,
    ];
    final grilleSlotIndex = _resolveGrilleSlotIndex(
      orderedKeys: orderedKeys,
      finalSections: sections,
    );
    return FluxContinuState(
      sections: sections,
      grilleSlotIndex: grilleSlotIndex,
      isSerene: isSerene,
      isSkeleton: true,
      isLoading: false,
    );
  }

  /// Coquilles de sections thème/sujet/veille pour le squelette, dérivées des
  /// favoris locaux (réutilise `_pickFavorites` + les mêmes label/accent que
  /// [_shellThemeSections]). `topFallback` vide ⇒ comptes neufs voient les
  /// thèmes canoniques (tech/env/science), ce qui rend une structure utile.
  List<FeedThemeSection> _skeletonThemeSections() =>
      _shellThemeSections(_pickFavorites(const <TopTheme>[]).refs);

  /// Coquilles (en-têtes vides) des sections thème/sujet/veille pour [refs],
  /// dans l'ordre fourni. Partagé par le squelette de démarrage
  /// ([_skeletonThemeSections]) et le **seed pré-fan-out** ([_buildStateFromPayload]) :
  /// même label/accent que le rendu réel, `items` vide, `hasMore: false`. Le
  /// fan-out remplace ensuite chaque coquille en place (cf. [_upsertByKey]).
  List<FeedThemeSection> _shellThemeSections(List<FavoriteRef> refs) {
    final interestsState = _peekValue(userInterestsProvider);
    final sections = <FeedThemeSection>[];
    for (final favRef in refs) {
      final FeedThemeSection? shell = switch (favRef) {
        ThemeFavoriteRef(:final slug) => FeedThemeSection(
            kind: SectionKind.theme,
            label: visualFor(slug).label,
            accent: visualFor(slug).accent,
            illustrationAsset: _kVeilleIllustration,
            coreVisibleCount: 3,
            themeSlug: slug,
            items: const [],
            hasMore: false,
            isPlaceholder: true,
          ),
        CustomTopicFavoriteRef(:final id) => FeedThemeSection(
            kind: SectionKind.theme,
            label: _customTopicLabel(interestsState, id),
            accent: _customTopicAccent(interestsState, id),
            illustrationAsset: _kVeilleIllustration,
            coreVisibleCount: 3,
            customTopicId: id,
            items: const [],
            hasMore: false,
            isPlaceholder: true,
          ),
        VeilleFavoriteRef() => _skeletonVeilleSection(),
      };
      if (shell != null) sections.add(shell);
    }
    return sections;
  }

  FeedThemeSection? _skeletonVeilleSection() {
    final activeCfg = _peekValue(veilleActiveConfigProvider);
    if (activeCfg == null) return null;
    return FeedThemeSection(
      kind: SectionKind.veille,
      label: 'Ma veille — ${activeCfg.sectionLabel}',
      blurb: 'Les derniers articles de ta veille personnalisée.',
      accent: _kVeilleAccent,
      illustrationAsset: _kVeilleIllustration,
      coreVisibleCount: 3,
      items: const [],
      hasMore: false,
      isPlaceholder: true,
    );
  }

  /// Coquilles de sections source pour le squelette, résolues via le même
  /// catalogue/sélection que [_shellSourceSections] (label/logo/accent réels).
  List<FeedThemeSection> _skeletonSourceSections() =>
      _shellSourceSections(_pickFavoriteSources());

  /// Force la résolution du catalogue `userSourcesProvider` quand des favoris
  /// source doivent être rendus et qu'il n'est pas encore disponible : sans lui,
  /// [_shellSourceSections] et le fan-out droppent chaque favori
  /// (`if (src == null) continue`) pour tout le cycle — la section n'apparaît
  /// alors qu'au cold boot suivant.
  ///
  /// Best-effort : borné à [_kSourceCatalogWait], erreur avalée. Renvoie `true`
  /// seulement si le catalogue **vient** d'être résolu (⇒ re-seed nécessaire) ;
  /// no-op (donc `false`) dans le cas nominal où il l'est déjà.
  Future<bool> _ensureSourceCatalog(List<SourceFavoriteRef> favs) async {
    if (favs.isEmpty) return false;
    if (ref.read(userSourcesProvider).hasValue) return false;
    try {
      await ref.read(userSourcesProvider.future).timeout(_kSourceCatalogWait);
    } catch (e) {
      debugPrint('FluxContinu: userSources catalog unresolved: $e');
    }
    return !_disposed && ref.read(userSourcesProvider).hasValue;
  }

  /// Coquilles (en-têtes vides) des sections source pour [favs], dans l'ordre
  /// fourni. Partagé par le squelette et le **seed pré-fan-out** : label/logo/
  /// accent réels (catalogue `userSourcesProvider`), `items` vide. Un favori
  /// dont la source n'est pas (encore) au catalogue est ignoré ce cycle.
  List<FeedThemeSection> _shellSourceSections(List<SourceFavoriteRef> favs) {
    if (favs.isEmpty) return const [];
    final catalog =
        _peekValue(userSourcesProvider) ?? const <Source>[];
    final sourceById = {for (final s in catalog) s.id: s};
    final sections = <FeedThemeSection>[];
    for (final fav in favs) {
      final src = sourceById[fav.sourceId];
      if (src == null) continue;
      sections.add(FeedThemeSection(
        kind: SectionKind.source,
        label: src.name,
        accent: sourceAccentFor(src.id),
        coreVisibleCount: 3,
        sourceId: src.id,
        sourceLogoUrl: src.logoUrl,
        items: const [],
        hasMore: false,
        isPlaceholder: true,
      ));
    }
    return sections;
  }

  /// Issue #1 — coquilles (placeholders) des sections « Choisie pour vous »
  /// seedées AVANT le fan-out, pour qu'elles ne « poppent » plus en net-new mais
  /// se remplissent **sur place**. Mêmes label/accent/reason/clé que
  /// [_buildSuggestedSection] (source → catalogue `userSourcesProvider` ; thème →
  /// vocabulaire `visualFor`) ⇒ l'upsert par `sectionKey` substitue la coquille.
  /// Une suggestion source absente du catalogue est ignorée (le builder la
  /// dropperait aussi). `origin: suggested`, `items` vides, `isPlaceholder: true`.
  List<FeedThemeSection> _shellSuggestedSections(
    List<TopTheme> usableSuggestions,
  ) {
    final catalog =
        _peekValue(userSourcesProvider) ?? const <Source>[];
    final sourceById = {for (final s in catalog) s.id: s};
    final sections = <FeedThemeSection>[];
    for (final s in usableSuggestions) {
      if (s.kind == 'source' && s.sourceId != null) {
        final src = sourceById[s.sourceId!];
        if (src == null) continue;
        sections.add(FeedThemeSection(
          kind: SectionKind.source,
          label: src.name,
          accent: sourceAccentFor(src.id),
          coreVisibleCount: 3,
          sourceId: src.id,
          sourceLogoUrl: src.logoUrl,
          items: const [],
          hasMore: false,
          origin: SectionOrigin.suggested,
          reason: s.reason,
          isPlaceholder: true,
        ));
      } else {
        final visual = visualFor(s.interestSlug);
        sections.add(FeedThemeSection(
          kind: SectionKind.theme,
          label: visual.label,
          accent: visual.accent,
          illustrationAsset: _kVeilleIllustration,
          coreVisibleCount: 3,
          themeSlug: s.interestSlug,
          items: const [],
          hasMore: false,
          origin: SectionOrigin.suggested,
          reason: s.reason,
          isPlaceholder: true,
        ));
      }
    }
    return sections;
  }

  FluxContinuState _compose(bool isSerene) {
    final tournee = ref.read(tourneeOrderPrefsProvider);
    final grilleAvailable = _peekValue(grilleProvider)?.today != null;
    final sectionByKey = _tourneeSectionByKey();

    // Cohérence Tournée — classification maigre/riche **et** scores de bloc, sur
    // l'ordre par défaut **non cappé** (la maigreur comme le score ne se
    // connaissent qu'après dédup, cf. plan). `thinKeys` sert au backfill et à la
    // modal favoris ; `blockScores` sert à l'ordre (gelé) et à la mesure.
    final (:thinKeys, :blockScores) = _classifyFavoriteSections(
      isSerene: isSerene,
      tournee: tournee,
      sectionByKey: sectionByKey,
    );
    // PR-4 — le gel consomme les scores que l'on vient de calculer, **avant**
    // [_orderedTourneeKeys] : l'ordre trié s'applique donc dès cette
    // recomposition. Drapeau armé à la complétion du fan-out — seul moment où
    // le set est stabilisé — plutôt qu'un 2ᵉ appel à [_classifyFavoriteSections]
    // qui rejouerait la passe ordre+dédup entière pour le même résultat.
    if (_freezeScoreOrderOnNextCompose) {
      _freezeScoreOrderOnNextCompose = false;
      _freezeScoreOrder(blockScores);
    }

    final orderedKeys = _orderedTourneeKeys(
      isSerene: isSerene,
      customized: tournee.customized,
      sectionByKey: sectionByKey,
      grilleAvailable: grilleAvailable,
      hiddenKeys: tournee.hiddenKeys,
      order: tournee.order,
      // Déclassement qualité — gelé avec l'ordre du jour, donc vide tant que le
      // 1ᵉʳ fan-out n'a pas abouti (aucun bloc ne bouge pendant le remplissage).
      poorKeys: _poorBlockKeys,
      // Ordre **gelé pour la journée** (null tant que le 1ᵉʳ fan-out du jour
      // n'a pas abouti) : zéro saut de bloc pendant le remplissage progressif.
      scoreOrder: _scoreOrderKeys,
    );

    // « Cartes ≤ écran » : décidé côté provider par estimation conservatrice
    // (pas de mesure runtime qui pilote le rendu). `null` au 1ᵉʳ frame ⇒ on
    // garde les défauts, on recompose à l'arrivée de la mesure.
    final usableHeight = ref.read(usableViewportHeightProvider);

    // Cloches « source rare » ayant du neuf non lu. Elles seules justifient le
    // rappel : une cloche silencieuse n'a rien à annoncer.
    final alerted =
        _peekValue(alertsProvider)?.withNewContent ??
            const <AlertItem>[];

    final rawOrdered = <FluxSection>[
      // Héros jamais tronqué (PO) : ses 5 articles entrent tous dans `seen` via
      // [_dedupeSectionsInOrder] → les sections aval portant le même contentId
      // les retirent correctement (pas de doublon).
      if (_essentiel != null) _fitHeroSection(_essentiel!, usableHeight),
      // Rappel d'alertes juste sous le héros — hors de `orderedKeys`, donc hors
      // du cap de sections : c'est un signal, il ne prend la place d'aucun thème.
      if (alerted.isNotEmpty) AlertsSection(items: alerted),
      for (final key in orderedKeys)
        if (key != kTourneeGrilleKey && sectionByKey[key] != null)
          sectionByKey[key]!,
      // Story 32.1 — carrousel du jour inséré directement (comme AlertsSection),
      // en toute fin de Tournée (après les Cartes Suggérées, avant la clôture).
      // Hors de `orderedKeys` donc hors du cap de sections, et non déplaçable.
      // Auto-porté : traverse dédup/fit intact (cf. _capSectionToFit /
      // _dedupeSectionsInOrder). Présent uniquement quand le backend l'a servi
      // (édition du jour + type éligible).
      if (_essentielCarousel != null) CarouselSection(data: _essentielCarousel!),
    ];
    // Dédup réel (ordre dépriorisé) en capturant les retirés par section, puis
    // réinjection (backfill) des sections favorites maigres **affichées**.
    final removedByKey = <String, List<Content>>{};
    final deduped = _dedupeSectionsInOrder(
      _filterSections(rawOrdered),
      removedByKey: removedByKey,
    );
    // Masquage (règle PO V1) : un bloc sous le plancher [kSectionMinItems]
    // **après** backfill n'a rien à montrer → il sort du flux, et sa clé part à
    // la modal pour que l'utilisateur sache pourquoi (jamais de disparition
    // silencieuse, cf. `bug-essentiel-blocs-favoris-absents.md`).
    final starvedKeys = <String>{};
    final finalSections = _capSectionsToFit(
      _dropStarvedSections(
        _backfillThinSections(
          _dropEmptySuggested(deduped),
          thinKeys,
          removedByKey,
        ),
        starvedKeys,
      ),
      usableHeight,
    );
    final stampedSections = _stampFollowedCounts(finalSections);
    final grilleSlotIndex = _resolveGrilleSlotIndex(
      orderedKeys: orderedKeys,
      finalSections: stampedSections,
    );

    return FluxContinuState(
      sections: stampedSections,
      grilleSlotIndex: grilleSlotIndex,
      isSerene: isSerene,
      closingDismissed: _closingDismissed,
      dismissedIds: Set.unmodifiable(_dismissedIds),
      quote: _quote,
      isLoading: false,
      // Toutes les clés maigres (affichées ou hors cap) → la modal sait
      // lesquelles signaler.
      thinFavoriteKeys: thinKeys,
      // Blocs retirés du flux faute d'articles → la modal l'explique au lieu de
      // laisser l'utilisateur devant une section absente sans raison.
      starvedFavoriteKeys: Set.unmodifiable(starvedKeys),
      // PR-1 — dénominateur du CTR par bloc : le screen le repasse au
      // `SectionBlock` qui le porte jusqu'à l'event `article_impression`.
      blockScores: Map.unmodifiable(blockScores),
    );
  }

  /// Repère les sections **choisies** (thème/source/veille) qui n'atteignent pas
  /// le plancher d'affichage [kSectionMinItems] une fois la dédup inter-sections
  /// passée, sur l'ordre par défaut **non cappé** : ce sont les blocs à renflouer
  /// ([_backfillThinSections]) avant que le masquage ([_dropStarvedSections]) ne
  /// tranche. Exclut éditorial / suggérées / Grille. N'inspecte que les sections
  /// au fetch résolu ([_resolvedSectionKeys]) → pas de faux positif sur des
  /// coquilles de boot.
  ///
  /// PR-4 — la même passe calcule les **scores de bloc** (`blockScores`, cf.
  /// `section_score_order.dart`), sur une portée volontairement **plus large**
  /// que le repérage des blocs sous plancher : toute `FeedThemeSection` résolue y
  /// entre, veille et « Choisie pour vous » comprises (une veille pauvre coule
  /// désormais elle aussi, décision PO). La map est en ordre d'affichage
  /// (insertion = parcours de `deduped`) : ses clés servent telles quelles de
  /// départage à score égal dans [rankKeysByBlockScore].
  ///
  /// Aucune circularité : cette passe appelle [_orderedTourneeKeys] **sans**
  /// `scoreOrder` (ordre par défaut, non cappé) — les scores ne dépendent donc
  /// pas de leur propre résultat. La dédup inter-sections arbitre ici les
  /// doublons dans l'ordre **par défaut**, mais elle ne pèse plus sur le score :
  /// un article partagé compte pour **chacune** des sections qui l'a servi (cf.
  /// `scorable` plus bas), donc l'attribution d'un doublon ne déplace plus le
  /// classement.
  ({Set<String> thinKeys, Map<String, double> blockScores})
      _classifyFavoriteSections({
    required bool isSerene,
    required TourneeOrderState tournee,
    required Map<String, FluxSection> sectionByKey,
  }) {
    // Veille incluse : elle est un bloc de la Tournée comme un autre, donc elle
    // profite du backfill avant d'être jugée en pénurie (le CTA « Ajouter des
    // sources » que porte `underfilled` reste, lui, réservé aux thèmes, cf.
    // `section_block.dart`).
    final favKeys = <String>{
      for (final s in _themes) sectionKey(s),
      for (final s in _sources) sectionKey(s),
    };
    final eligible = {
      for (final k in favKeys)
        if (_resolvedSectionKeys.contains(k) && sectionByKey.containsKey(k)) k,
    };
    // Sans favori résolu **ni** aucune autre section résolue (veille,
    // suggérées), il n'y a ni maigreur ni score à calculer. La 2ᵉ condition est
    // indispensable : un compte sans favori mais avec une veille résolue doit
    // quand même produire ses `blockScores`.
    if (eligible.isEmpty && _resolvedSectionKeys.isEmpty) {
      return (
        thinKeys: const <String>{},
        blockScores: const <String, double>{},
      );
    }

    final orderedKeys = _orderedTourneeKeys(
      isSerene: isSerene,
      customized: tournee.customized,
      sectionByKey: sectionByKey,
      grilleAvailable: false,
      hiddenKeys: tournee.hiddenKeys,
      order: tournee.order,
      cap: null, // passe non cappée : la maigreur se mesure sur tout l'ordre
      // Pas de `poorKeys` ici : la passe de classification produit les scores
      // dont le déclassement est dérivé — l'y appliquer serait circulaire.
    );
    final rawOrdered = <FluxSection>[
      if (_essentiel != null) _essentiel!,
      for (final key in orderedKeys)
        if (key != kTourneeGrilleKey && sectionByKey[key] != null)
          sectionByKey[key]!,
    ];
    // Bug « blocs favoris absents de l'Essentiel » — on capture ici aussi les
    // articles strippés par la dédup inter-sections : ils comptent dans le
    // **score** du bloc (cf. plus bas), pas dans sa maigreur.
    final removedByKey = <String, List<Content>>{};
    final deduped = _dedupeSectionsInOrder(
      _filterSections(rawOrdered),
      removedByKey: removedByKey,
    );

    final thinKeys = <String>{};
    final blockScores = <String, double>{};
    for (final s in deduped) {
      if (s is! FeedThemeSection) continue;
      final k = sectionKey(s);
      // Le score juge la **qualité du bloc**, pas ce que la dédup lui a laissé :
      // on score sur les articles que le backend a réellement servis pour ce
      // bloc, retirés compris. Sans ça, un thème dont les meilleurs articles
      // sont montés dans le héros (ou dans les Actus du jour) — donc précisément
      // un thème très pertinent ce matin-là — se retrouvait vidé par
      // [_dedupeSectionsInOrder], scorait ~0 et coulait en bas de Tournée, voire
      // hors du cap. C'est le cas rapporté : « j'avais des articles tech/climat
      // dans ma pile de tri et je n'ai pas vu ces sections ».
      //
      // La maigreur (`thinKeys`), elle, continue de se mesurer sur les
      // survivants : elle décrit ce qui sera **affiché** et pilote le backfill.
      final scorable = removedByKey[k] == null
          ? s.items
          : <Content>[...s.items, ...removedByKey[k]!];
      // Score de bloc : toute section résolue portant au moins un article scoré.
      // Une section dont **aucun** article n'a de `recommendationReason` (bloc
      // éditorial, veille sans scoring, coquille de boot) reste hors de la map
      // → elle garde sa place au lieu de couler à 0.
      //
      // Volontairement **hors** de [kTourneeScoreSortEnabled] : le kill-switch
      // désarme le *tri*, pas la *mesure*. Le couper ferait retomber
      // `block_score` à `null` sur `article_impression` (PR-1) — donc
      // aveuglerait l'instrument même qui sert à juger le tri.
      if (_resolvedSectionKeys.contains(k) &&
          scorable.any((c) => c.recommendationReason != null)) {
        blockScores[k] = blockScore(scorable);
      }
      if (!eligible.contains(k)) continue;
      // « Maigre » = sous le plancher d'affichage : c'est exactement l'ensemble
      // des blocs qu'il faut tenter de renflouer avant de décider un masquage.
      if (s.items.length < kSectionMinItems) thinKeys.add(k);
    }
    return (
      thinKeys: thinKeys,
      blockScores: blockScores,
    );
  }

  /// Blocs favoris dont la **curation du jour** est pauvre : score de bloc sous
  /// [kPoorBlockScoreRatio] × la médiane des blocs favoris scorés.
  ///
  /// Médiane plutôt que moyenne (insensible au bloc vedette qui écraserait tout)
  /// et seuil **relatif** plutôt qu'absolu : `blockScore` est une somme de scores
  /// backend, dont l'échelle varie d'un utilisateur et d'un jour à l'autre. Le
  /// jour où tout est bon, personne n'est déclassé — c'est l'effet voulu, le
  /// déclassement dit « ce bloc est en retrait *aujourd'hui* », pas « ce bloc est
  /// mauvais ».
  ///
  /// Ne juge que les blocs **choisis** (thème/source/veille) : une suggestion
  /// n'a pas à peser sur la médiane, elle passe déjà après eux.
  Set<String> _poorFavoriteKeys(Map<String, double> blockScores) {
    final favKeys = <String>{
      for (final s in _themes) sectionKey(s),
      for (final s in _sources) sectionKey(s),
    };
    final scored = <String, double>{
      for (final e in blockScores.entries)
        if (favKeys.contains(e.key)) e.key: e.value,
    };
    if (scored.length < kPoorDemotionMinBlocks) return const {};

    final values = scored.values.toList()..sort();
    final mid = values.length ~/ 2;
    final median = values.length.isOdd
        ? values[mid]
        : (values[mid - 1] + values[mid]) / 2;
    // Médiane nulle : tous les blocs sont à 0 (aucun article scoré ce jour-là).
    // Rien à départager — déclasser la moitié du flux au hasard serait pire.
    if (median <= 0) return const {};

    final threshold = median * kPoorBlockScoreRatio;
    return {
      for (final e in scored.entries)
        if (e.value < threshold) e.key,
    };
  }

  /// Retire du flux les blocs qui n'atteignent pas le plancher d'affichage
  /// [kSectionMinItems] — après backfill, donc en dernier recours — et collecte
  /// leurs clés dans [starvedKeys] pour la modal « Mes favoris ».
  ///
  /// Deux garde-fous contre le clignotement pendant le fan-out (10-15
  /// recompositions) : on ne juge que les sections dont le fetch a **résolu**
  /// ([_resolvedSectionKeys]) et jamais une coquille de squelette
  /// (`isPlaceholder`) — sinon chaque bloc disparaîtrait puis réapparaîtrait à
  /// l'arrivée de sa réponse.
  List<FluxSection> _dropStarvedSections(
    List<FluxSection> sections,
    Set<String> starvedKeys,
  ) {
    final kept = <FluxSection>[];
    for (final s in sections) {
      if (s is! FeedThemeSection || s.isPlaceholder) {
        kept.add(s);
        continue;
      }
      final k = sectionKey(s);
      if (!_resolvedSectionKeys.contains(k) ||
          s.items.length >= kSectionMinItems) {
        kept.add(s);
        continue;
      }
      starvedKeys.add(k);
    }
    return kept;
  }

  /// Réinjecte dans chaque section favorite **maigre affichée** (clé ∈
  /// [thinKeys]) des articles strippés par la dédup ([removedByKey]) jusqu'à
  /// [kSectionMinItems], et marque la section `underfilled` (pilote le CTA
  /// thème « Ajouter plus de sources »). Doublons inter-sections assumés (PO) ;
  /// dédup intra-section préservée.
  ///
  /// C'est la **dernière chance** d'un bloc avant [_dropStarvedSections] : le
  /// backfill vise donc le plancher d'affichage, pas un palier intermédiaire.
  /// Un thème dont le héros a pris les meilleurs articles les récupère ici et
  /// reste affiché — c'est précisément le cas qui faisait disparaître Technologie
  /// et Environnement.
  List<FluxSection> _backfillThinSections(
    List<FluxSection> sections,
    Set<String> thinKeys,
    Map<String, List<Content>> removedByKey,
  ) {
    if (thinKeys.isEmpty) return sections;
    return [
      for (final s in sections)
        if (s is FeedThemeSection && thinKeys.contains(sectionKey(s)))
          _backfillOneThinSection(s, removedByKey[sectionKey(s)] ?? const [])
        else
          s,
    ];
  }

  FeedThemeSection _backfillOneThinSection(
    FeedThemeSection s,
    List<Content> removed,
  ) {
    final seen = {for (final c in s.items) c.id};
    final additions = <Content>[];
    for (final c in removed) {
      if (s.items.length + additions.length >= kSectionMinItems) break;
      if (seen.add(c.id)) additions.add(c);
    }
    // `underfilled` toujours vrai (section maigre affichée) → CTA thème même si
    // rien n'a pu être réinjecté ; `items` n'est touché que s'il y a des ajouts.
    return s.copyWith(
      items: additions.isEmpty ? null : [...s.items, ...additions],
      underfilled: true,
    );
  }

  /// La carte héros « Ton Essentiel » n'est **jamais tronquée** (PO) : ses
  /// 5 articles du jour sont toujours affichés, quel que soit le viewport.
  /// No-op conservé comme seam (appelé par [_compose]).
  FluxSection _fitHeroSection(FluxSection essentiel, double? usableHeight) {
    return essentiel;
  }

  /// Story 22.5 — (re)stampe `followedSourceCount` sur les sections **thème**
  /// (macro-thème avec `themeSlug`) depuis `themesFollowedProvider`. Appelé en
  /// toute fin de [_compose] : source unique de vérité, insensible au timing du
  /// provider lazy (au 1ᵉʳ compose il est null → count 0 → « Ajouter » ; sa
  /// résolution déclenche un recompose via le listener de build() → re-stamp).
  /// Les sujets custom (`themeSlug == null`) et thèmes absents du provider
  /// gardent 0.
  List<FluxSection> _stampFollowedCounts(List<FluxSection> sections) {
    final themes = _peekValue(themesFollowedProvider);
    if (themes == null || themes.isEmpty) return sections;
    final bySlug = {for (final t in themes) t.slug: t.followedSourcesCount};
    return [
      for (final s in sections)
        if (s is FeedThemeSection &&
            s.themeSlug != null &&
            bySlug.containsKey(s.themeSlug))
          s.copyWith(followedSourceCount: bySlug[s.themeSlug])
        else
          s,
    ];
  }

  /// Story 22.3 — retire les sections **suggérées** vidées par le dédup
  /// inter-sections (tous leurs articles déjà vus plus haut). Une « Choisie
  /// pour vous » sans article ne doit jamais afficher un bandeau + badge
  /// orphelins (contrairement aux sections validées source/veille qui rendent
  /// un empty-state assumé).
  List<FluxSection> _dropEmptySuggested(List<FluxSection> sections) {
    return [
      for (final s in sections)
        if (!(s is FeedThemeSection && s.isSuggested && s.items.isEmpty)) s,
    ];
  }

  /// Caps each downstream section's `coreVisibleCount` to what fits the usable
  /// viewport. Le fit dépend du mode (`DisplayModeSpec`) : il peut monter ou
  /// descendre jusqu'à `min(ceiling, totalCount)` (plancher dur 2). The hero is
  /// handled upstream (trim de la liste), so it passes through.
  List<FluxSection> _capSectionsToFit(
    List<FluxSection> sections,
    double? usableHeight,
  ) {
    // Mesure absente (1ᵉʳ frame) OU implausiblement petite (render box détachée /
    // recompose hors-écran) : on applique malgré tout un cap **dépendant du
    // mode** sur une hauteur de référence, JAMAIS le nominal backend mode-aveugle
    // (qui déborde en Lisible : 3 grosses cartes ; et sous-remplit en
    // Minimaliste). La vraie mesure affine ensuite dès qu'elle arrive.
    final effectiveHeight =
        (usableHeight != null && usableHeight >= kMinPlausibleUsableHeight)
            ? usableHeight
            : kReferenceUsableHeight;
    return [for (final s in sections) _capSectionToFit(s, effectiveHeight)];
  }

  FluxSection _capSectionToFit(FluxSection s, double usableHeight) {
    if (s is EssentielSection) return s;
    // Le rappel d'alertes est un signal contextuel de taille fixe (≤3 lignes),
    // pas une section de contenu qui se dispute la hauteur d'écran.
    if (s is AlertsSection) return s;
    // La carte carrousel est auto-portée (PageView à hauteur fixe) : elle
    // échappe au fit vertical (Story 32.1), comme le rappel d'alertes.
    if (s is CarouselSection) return s;
    // Issue #1 — une coquille (placeholder, `totalCount == 0`) doit **réserver**
    // sa hauteur nominale (`coreVisibleCount`). Sans ce court-circuit, le fit
    // rabattrait son compte à 1 (pool vide) et la réserve squelette ne ferait
    // qu'1 carte → l'upsert décalerait quand même le bas de page. On la laisse
    // intacte ; le fit réel s'applique dès que le contenu est résolu.
    if (s is FeedThemeSection && s.isPlaceholder) return s;
    final hasBlurb = s.blurb?.trim().isNotEmpty ?? false;
    final spec = ref.read(displayModeSpecProvider);
    // Le cap intervient après dédup, donc les articles révélés au-dessus du
    // nominal sont déjà dédupliqués. Chaque mode porte son plafond (cf.
    // DisplayModeSpec) : le fit peut **monter** OU **descendre** jusqu'à
    // `min(ceiling, totalCount)` pour remplir l'écran selon le mode,
    // indépendamment du nominal backend.
    final ceiling = spec.sectionFitCeiling;
    final maxCount = ceiling == null
        ? s.coreVisibleCount
        : math.max(1, math.min(ceiling, s.totalCount));
    // Plancher dur : **jamais 1 seul article** dès qu'au moins 2 sont
    // disponibles (même en Lisible sur un petit écran — la cible « remplir sans
    // déborder » ne doit pas tomber à 1). Borné au pool réel pour ne pas
    // inventer de carte.
    final minCount = math.min(2, s.totalCount);
    // Certains footers (« Tout lire › » sur digest/source, « Ajouter plus de
    // sources » replié sur un thème riche) ajoutent de la hauteur **réelle sous
    // les cartes** que la mesure de snap voit (box.size.height footer inclus).
    // On la réserve dans le budget pour que l'estimation classe la section comme
    // la mesure la classera — sinon bascule *tall* parasite (cf. plan snap).
    final footerReserve = estimateSectionFooterReserve(
      isDigest: s is DigestTopicSection,
      isSourceNonEmpty: s is FeedThemeSection &&
          s.kind == SectionKind.source &&
          s.items.isNotEmpty,
      isRichThemeWithSlug: s is FeedThemeSection &&
          s.kind == SectionKind.theme &&
          !s.underfilled &&
          s.themeSlug != null &&
          s.items.isNotEmpty,
    );
    // Crédit de la marge basse de la dernière carte (espace blanc sous le pli,
    // aucun contenu) : sinon une section reste à N−1 alors qu'une Nᵉ carte tient
    // à 12px près — cf. kLastCardBottomMargin. **Sauf** quand un footer suit la
    // dernière carte (footerReserve > 0) : sa marge basse n'est plus sous le pli
    // (le footer la recouvre), donc pas de crédit.
    final lastCardMarginCredit =
        footerReserve > 0 ? 0.0 : kLastCardBottomMargin;
    final fitCap = fitVisibleCount(
      usableHeight: usableHeight + lastCardMarginCredit,
      bannerHeight: hasBlurb ? kBannerHeightWithBlurb : kBannerHeightNoBlurb,
      // Réserve du footer réel de la section (0 quand aucun footer contenu ne
      // suit les cartes : seul le gap de fin de section, qui glisse hors écran).
      footerHeight: footerReserve,
      cardHeight: estimateRegularCardHeight(spec),
      maxCount: maxCount,
      minCount: minCount,
    );
    if (fitCap == s.coreVisibleCount) return s;
    return switch (s) {
      EssentielSection() => s,
      AlertsSection() => s,
      CarouselSection() => s,
      DigestTopicSection() => DigestTopicSection(
          kind: s.kind,
          label: s.label,
          accent: s.accent,
          coreVisibleCount: fitCap,
          blurb: s.blurb,
          illustrationAsset: s.illustrationAsset,
          topics: s.topics,
        ),
      FeedThemeSection() => s.copyWith(coreVisibleCount: fitCap),
    };
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
              newSinceMorning: s.newSinceMorning,
              carousel: s.carousel,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
            ),
          // Un swipe porte sur un article ; le rappel d'alertes n'en liste pas.
          AlertsSection() => s,
          // Le carrousel est un scroller horizontal auto-porté : le swipe
          // vertical de dismiss ne s'y applique pas (traversée intacte).
          CarouselSection() => s,
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
  /// [removedByKey] (optionnel) collecte, par `sectionKey` de section
  /// [FeedThemeSection], les `Content` **strippés** par la dédup (déjà vus plus
  /// haut). Sert à la réinjection (backfill) des sections favorites maigres dans
  /// [_compose] : on y repioche des articles ≤72h déjà renvoyés par le backend
  /// (doublons inter-sections assumés, décision PO).
  List<FluxSection> _dedupeSectionsInOrder(
    List<FluxSection> sections, {
    Map<String, List<Content>>? removedByKey,
  }) {
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
              newSinceMorning: s.newSinceMorning,
              carousel: s.carousel,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
            ),
          );
        case AlertsSection():
          // Aucun contentId à réserver : le rappel traverse la dédup intact.
          result.add(s);
        case CarouselSection():
          // Carte auto-portée (Story 32.1) : elle traverse la dédup intacte et
          // ne réserve pas ses ids (backend a déjà exclu les 5 de l'Essentiel ;
          // un rare doublon avec un thème vertical est assumé, hors-cap).
          result.add(s);
        case DigestTopicSection(:final topics):
          final kept = topics
              .where((t) => seen.add(pickTopicLead(t).contentId))
              .toList(growable: false);
          // Post-filtre : le dedup peut faire retomber « Actus du jour » sous
          // son plancher (kind=essentiel) → on réapplique le seuil pour éviter
          // un bandeau réduit à une carte isolée. Les autres DigestTopicSection
          // (Bonnes Nouvelles) ne sont retirées que si totalement vidées.
          final minKept =
              s.kind == SectionKind.essentiel ? _kActusMinTopics : 1;
          if (kept.length < minKept) continue;
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
          final kept = <Content>[];
          final removed = <Content>[];
          for (final c in items) {
            (seen.add(c.id) ? kept : removed).add(c);
          }
          if (removedByKey != null && removed.isNotEmpty) {
            removedByKey[sectionKey(s)] = removed;
          }
          result.add(s.copyWith(items: kept));
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
              newSinceMorning: s.newSinceMorning,
              carousel: s.carousel,
              blurb: s.blurb,
              illustrationAsset: s.illustrationAsset,
            ),
          // Le compteur d'une cloche vient du serveur (contenus non lus ≤24h) :
          // il se corrige au prochain `refresh`, pas article par article.
          AlertsSection() => s,
          // Le carrousel reflète l'état « lu » de ses items au prochain refresh
          // (comme le rappel d'alertes) — pas de mutation article par article.
          CarouselSection() => s,
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
          FeedThemeSection(:final items) => s.copyWith(
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
      final offset = (nextPage - 1) * kThemeSectionPageLimit;
      response = await _safe<FeedResponse>(
        () => ref.read(fluxContinuRepositoryProvider).getVeilleFeedItems(
              limit: kThemeSectionPageLimit,
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
          limit: kThemeSectionPageLimit,
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
      //
      // Étendu à TOUTE la Tournée (`renderedContentIds`) : le dedup
      // inter-sections ne tourne que dans [_compose], que `loadMoreTheme` ne
      // rejoue pas. Sans ça une page 2 pouvait ré-afficher un article déjà
      // rendu par l'Essentiel ou Actus du jour, juste sous la page 1 qui, elle,
      // en avait été purgée. Coût : un parcours des sections déjà en mémoire.
      final existingIds = {
        ...renderedContentIds(afterCurrent.sections),
        for (final item in afterTarget.items) item.id,
      };
      final appended = [
        ...afterTarget.items,
        for (final item in response.items)
          if (!existingIds.contains(item.id)) item,
      ];
      // Terminateur : une page non vide dont AUCUN item ne survit à la dédup
      // n'a rien apporté. Sans ce garde-fou la section garderait `hasMore=true`
      // sans jamais grandir → indicateur de chargement permanent, carte de
      // clôture (« Vous êtes à jour ») et bloc « Section suivante » jamais
      // atteignables. Remplace, en plus précis, l'ancienne règle
      // « page incomplète ⇒ hasMore=false » qui coupait aussi les cas sains.
      final producedNothing = appended.length == afterTarget.items.length;
      final hasMore = !producedNothing &&
          _themeHasMore(
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

  /// Hydrate [_scoreOrderKeys] depuis les prefs pour la journée courante.
  /// No-op si l'ordre du jour est déjà en mémoire — indispensable car la
  /// persistance est `unawaited` : un refresh immédiat après le gel relirait
  /// sinon une valeur périmée.
  Future<void> _loadScoreOrderForToday() async {
    if (!kTourneeScoreSortEnabled) {
      _scoreOrderDayKey = null;
      _scoreOrderKeys = null;
      _poorBlockKeys = const {};
      return;
    }
    final today = TourneeProgressService.dayKey(DateTime.now());
    if (_scoreOrderDayKey == today) return;
    _scoreOrderDayKey = null;
    _scoreOrderKeys = null;
    _poorBlockKeys = const {};
    final service = ref.read(tourneeProgressServiceProvider);
    final loaded = await service.loadScoreOrderForToday();
    if (loaded != null && loaded.isNotEmpty) {
      _scoreOrderDayKey = today;
      _scoreOrderKeys = loaded;
      // Déclassement gelé le même jour, dans la même entrée : il ne survit
      // jamais à l'ordre auquel il appartient.
      _poorBlockKeys = await service.loadPoorKeysForToday() ?? const {};
    }
  }

  /// Gèle l'ordre des blocs pour la journée à partir des [scores] que
  /// [_compose] vient de calculer, s'il ne l'est pas déjà. Armé **une fois**,
  /// à la complétion du fan-out : tout est stabilisé, donc les scores sont ceux
  /// du set complet.
  ///
  /// Le classement se fait sur les clés de [scores] — la map est en ordre
  /// d'affichage, donc l'ordre manuel/par défaut départage à score égal (le tri
  /// est stable). Les sections non scorées ne sont pas dans la map : elles
  /// garderont leur place à l'application (cf. [applyScoreOrder]).
  ///
  /// Story 22.7 — les sections-source **suggérées** sont retirées de l'ordre
  /// gelé : leur position doit suivre le seul `daily_rank` backend, qui porte
  /// déjà la démotion « thèmes d'abord, sources ensuite » atténuée par la
  /// pertinence. Sans ce filtre, un média jamais consulté avec un article
  /// « chaud » remonterait au-dessus des thèmes que l'utilisateur vient de
  /// choisir. Le filtre porte sur l'**ordre**, jamais sur la **mesure** :
  /// `scores` (donc `block_score` sur `article_impression`) reste intact.
  void _freezeScoreOrder(Map<String, double> scores) {
    if (!kTourneeScoreSortEnabled) return;
    final today = TourneeProgressService.dayKey(DateTime.now());
    if (_scoreOrderDayKey == today) return;
    if (scores.isEmpty) return; // rien de scoré ce cycle → ordre par défaut.

    final pinned = _suggestedSourceKeys;
    final frozen = [
      for (final k in rankKeysByBlockScore(scores))
        if (!pinned.contains(k)) k,
    ];
    // Que des sections-source suggérées → rien à trier.
    if (frozen.isEmpty) return;
    // Le déclassement qualité est gelé **ici**, depuis les mêmes scores que
    // l'ordre : les deux ne peuvent donc pas diverger, et un « Voir +10 » plus
    // tard dans la journée ne fait pas remonter un bloc déclassé.
    final poor = _poorFavoriteKeys(scores);
    _scoreOrderDayKey = today;
    _scoreOrderKeys = frozen;
    _poorBlockKeys = poor;
    unawaited(
      ref
          .read(tourneeProgressServiceProvider)
          .setScoreOrderToday(frozen, poorKeys: poor),
    );
  }

  /// Marks that the user has actually loaded Essentiel content today, so the
  /// app can default to Flâner on the next cold start / resume. Write-once
  /// per notifier instance to avoid redundant prefs writes on refetches.
  Future<void> _markEssentielViewedIfNeeded() async {
    if (_essentielViewedMarked) return;
    _essentielViewedMarked = true;
    await ref.read(tourneeProgressServiceProvider).markEssentielViewedToday();
  }

  /// Budget maximal d'un pull-to-refresh. Un appel nominal se résout bien en
  /// dessous ; ce plafond coupe le pire cas (chaque appel Dio = 30s timeout +
  /// [RetryInterceptor] `[1s, 3s]` ⇒ ~94s) qui faisait tourner le
  /// [RefreshIndicator] > 20s. Vit **uniquement** sur le chemin [refresh] :
  /// [_fetchAll] (build/cold-boot) et les retries globaux restent intacts.
  static const _kRefreshBudget = Duration(seconds: 8);

  /// Pull-to-refresh: refetch all upstream calls from scratch, borné à
  /// [_kRefreshBudget].
  ///
  /// Crucially we do NOT bounce through [AsyncLoading] — doing so would
  /// tear down the [RefreshIndicator] mid-pull (the screen renders the
  /// loading skeleton in place of the scroll view), making the gesture
  /// feel broken. Keeping the previous data mounted lets the native
  /// indicator stay visible until the refetch resolves.
  ///
  /// Renvoie un record léger permettant à l'écran de distinguer « rien de neuf »
  /// (`succeeded=true`, `newSinceMorning==0`) d'un refresh borné/échoué
  /// (`succeeded=false` — on ne redirige alors PAS vers Flâner, ce serait
  /// masquer un souci de perf). En cas de timeout/erreur **avec** un état déjà
  /// monté, on **conserve** les données précédentes (le spinner s'arrête net,
  /// feed inchangé, pas d'écran d'erreur). Le [_fetchAll] abandonné continue en
  /// arrière-plan (Dart n'a pas d'annulation sans `CancelToken`) : ses futures
  /// Dio sont avalées par [_safe] (inoffensif) et son cache write final finit
  /// par s'exécuter avec du contenu frais — seul le spinner est borné, pas le
  /// travail sous-jacent.
  Future<({bool succeeded, int newSinceMorning})> refresh() async {
    final next =
        await AsyncValue.guard(() => _fetchAll().timeout(_kRefreshBudget));
    if (next.hasError) {
      // Refresh borné (timeout) ou échoué. Si on a déjà des données montées, on
      // les garde (contrat « keep previous data mounted ») ; sinon on remonte
      // l'erreur comme aujourd'hui (cold-boot sans donnée à préserver).
      if (!state.hasValue) state = next;
      return (succeeded: false, newSinceMorning: 0);
    }
    state = next;
    final value = next.value;
    return (
      succeeded: true,
      newSinceMorning: value == null ? 0 : _newSinceMorningOf(value),
    );
  }

  /// `new_since_this_morning` porté par l'[EssentielSection] d'un état, 0 si
  /// absente. Signal non-fragile consommé par l'escalade « rien de neuf ».
  int _newSinceMorningOf(FluxContinuState value) =>
      value.sections.whereType<EssentielSection>().firstOrNull?.newSinceMorning ??
      0;

  /// Builds the v3 "L'Essentiel du jour" hi-fi section from the 5 articles
  /// returned by `GET /api/essentiel`. Returns `null` when the endpoint hasn't
  /// produced anything yet (202 preparing or transient failure) so the screen
  /// degrades gracefully — Bonnes Nouvelles + thèmes restent visibles.
  ///
  /// **Convention du héros, une seule règle, deux états distincts** (passe PO
  /// 09/08, défaut A1) :
  ///
  /// - `_essentiel == null` ⇒ **résolu à rien** : aucune carte héros n'est
  ///   rendue. C'est ce que renvoie cette fonction sur une liste vide.
  /// - `EssentielSection(articles: [])` ⇒ **pas encore résolu** : la coquille
  ///   posée par [_buildSkeletonState]. La carte rend alors la **silhouette**
  ///   de la pile (cf. `contentPending` dans `EssentielHiFiCard`), jamais son
  ///   en-tête seul.
  ///
  /// La distinction compte parce que la coquille **échappe** au squelette
  /// d'écran : [_reconcilePlacementThenSync] publie un `_compose()`
  /// non-squelette pendant le bootstrap (délibérément non gardé par
  /// `_bootstrapping`, cf. « race 1 »), donc un état `isSkeleton: false` peut
  /// porter le héros vide bien avant que `_fetchAll` n'ait résolu quoi que ce
  /// soit.
  FluxSection? _buildEssentielSection(
    List<EssentielArticle> articles, {
    int newSinceMorning = 0,
  }) {
    if (articles.isEmpty) return null;
    return EssentielSection(
      articles: articles,
      newSinceMorning: newSinceMorning,
      // Carrousel du jour porté jusqu'à la carte pour « Voir d'autres articles »
      // (réinjection dans la pile de tri, itération PO 33.1). Déjà mémorisé
      // juste au-dessus (`_essentielCarousel = essentielCarousel`).
      carousel: _essentielCarousel,
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
    int minTopics = 1,
  }) {
    final topics = digest?.topics
            .where((t) => t.articles.isNotEmpty)
            .toList(growable: false) ??
        const <DigestTopic>[];
    if (topics.length < minTopics) return null;
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
  /// `has_next` du backend, borné par « la page n'était pas vide ».
  ///
  /// L'ancienne règle exigeait une page **pleine**
  /// (`itemCount >= kThemeSectionPageLimit`) : dès qu'une page revenait courte
  /// alors que le backend annonçait `has_next: true`, la pagination était
  /// coupée **définitivement**. Ce cas est réel — `total_candidates` est figé
  /// côté serveur AVANT les post-filtres Python (entités mutées, filtre
  /// entité), donc `has_next` peut être vrai avec une page incomplète.
  /// On s'aligne sur Flâner (`feed_provider.dart` : `hasNext && isNotEmpty`).
  bool _themeHasMore(bool hasNext, int itemCount) => hasNext && itemCount > 0;

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
    SectionOrigin origin = SectionOrigin.validated,
    SuggestionReason? reason,
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
      origin: origin,
      reason: reason,
      // `followedSourceCount` n'est PAS stampé ici : `themesFollowedProvider`
      // est lazy → non résolu au 1ᵉʳ fan-out. Il est (re)stampé à la fin de
      // [_compose] ([_stampFollowedCounts]), qui re-tourne quand le provider
      // résout (listener dans build()). Défaut 0 en attendant.
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
  /// [_buildStateFromPayload] (pas de seed de coquilles pour le fallback) et le
  /// fan-out (`isExplicitFavorite`) pour décider de l'affichage d'un empty-state.
  ({List<FavoriteRef> refs, bool isFallback}) _pickFavorites(
    List<TopTheme> topFallback,
  ) {
    final favorites =
        _peekValue(userInterestsProvider)?.favorites ?? const [];

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
    final activeCfg = _peekValue(veilleActiveConfigProvider);
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
        // Story 22.3 — fini le triplet codé en dur (tech/env/science) : un
        // compte peu configuré est désormais complété par les sections
        // « Choisie pour vous » (suggestions backend, jamais hors préférences),
        // pas par des macro-thèmes statiques. On ne garde ici que les thèmes
        // réellement **validés** et pondérés (`origin=="validated"`) ; les
        // suggérées du même payload transitent par le fan-out progressif
        // (`_fanOutSectionsProgressive` → `_buildSuggestedSection`).
        final valid = topFallback
            .where(
                (t) => !t.isSuggested && themeMap.containsKey(t.interestSlug))
            .map<FavoriteRef>((t) => ThemeFavoriteRef(slug: t.interestSlug))
            .toList();
        themeRefs = valid.take(_kMaxFavoriteSections).toList(growable: false);
        isFallback = themeRefs.isNotEmpty;
      }
    }

    return (
      refs: [...themeRefs, if (veilleRef != null) veilleRef],
      isFallback: isFallback,
    );
  }

  /// Construit la section d'un favori thème / sujet / veille à partir de son
  /// `FeedResponse` déjà fetché. Partagé par le fan-out progressif
  /// ([_fanOutSectionsProgressive]) et le refetch ([_refetchThemesOnly]).
  FeedThemeSection? _buildFavoriteThemeSection(
    FavoriteRef favRef,
    FeedResponse? feed, {
    required bool isExplicitFavorite,
    UserInterestsState? interestsState,
  }) {
    final interests =
        interestsState ?? _peekValue(userInterestsProvider);
    return switch (favRef) {
      ThemeFavoriteRef(:final slug) => _buildThemeSection(
          feed: feed,
          label: visualFor(slug).label,
          accent: visualFor(slug).accent,
          themeSlug: slug,
          isExplicitFavorite: isExplicitFavorite,
        ),
      CustomTopicFavoriteRef(:final id) => _buildThemeSection(
          feed: feed,
          label: _customTopicLabel(interests, id),
          accent: _customTopicAccent(interests, id),
          customTopicId: id,
          isExplicitFavorite: isExplicitFavorite,
        ),
      // Story 23.2 PR-4 : la veille devient une section Tournée dédiée
      // avec son propre accent et label, calculée séparément des thèmes.
      VeilleFavoriteRef() => _buildVeilleSection(feed),
    };
  }

  /// `sectionKey` de la section que rendra [favRef] (thème/sujet/veille) — aligné
  /// sur [sectionKey] pour servir de clé `_resolvedSectionKeys` même quand le
  /// fetch renvoie une section nulle (aucune section à inspecter alors).
  String _favRefSectionKey(FavoriteRef favRef) => switch (favRef) {
        ThemeFavoriteRef(:final slug) => tourneeThemeKey(slug),
        CustomTopicFavoriteRef(:final id) => 'topic:$id',
        VeilleFavoriteRef() => kTourneeVeilleKey,
      };

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
      ThemeFavoriteRef(:final slug) => _fetchWithRetry<FeedResponse>(
          () => _feedRepo.getFeed(
            page: 1,
            limit: kThemeSectionPageLimit,
            theme: slug,
            serein: isSerene,
            personalized: true,
          ),
          'getFeed?theme=$slug&personalized=true',
        ),
      // Backend `/api/feed` accepts a UUID stringified in the `topic` param
      // (story 22.1) — looked up against `user_topic_profiles` scoped on the
      // current user, so no cross-user leak.
      CustomTopicFavoriteRef(:final id) => _fetchWithRetry<FeedResponse>(
          () => _feedRepo.getFeed(
            page: 1,
            limit: kThemeSectionPageLimit,
            topic: id,
            serein: isSerene,
            personalized: true,
          ),
          'getFeed?topic=$id&personalized=true',
        ),
      // Story 23.2 PR-4 : la veille est résolue via `/api/veille/feed`,
      // exposée par FluxContinuRepository.getVeilleFeedItems (normalise la
      // réponse en FeedResponse Content-compatible).
      VeilleFavoriteRef() => _fetchWithRetry<FeedResponse>(
          () => ref.read(fluxContinuRepositoryProvider).getVeilleFeedItems(
                limit: kThemeSectionPageLimit,
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
    final activeCfg = _peekValue(veilleActiveConfigProvider);
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
      label: 'Ma veille — ${activeCfg.sectionLabel}',
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
        _peekValue(userSourcesStateProvider)?.favorites ??
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

  Future<FeedResponse?> _fetchOneSource(String sourceId, bool isSerene) {
    // `personalized: true` + `source_id` ⇒ backend route vers le scoring
    // piliers (fenêtre adaptative 24→48→72h), mêmes critères que les sections
    // thème. Flâner appelle sans `personalized` → reste chronologique.
    return _fetchWithRetry<FeedResponse>(
      () => _feedRepo.getFeed(
        page: 1,
        limit: kThemeSectionPageLimit,
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
    SectionOrigin origin = SectionOrigin.validated,
    SuggestionReason? reason,
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
      origin: origin,
      reason: reason,
      noRecentSource: feed?.noRecentSource ?? false,
    );
  }

  // ---------------------------------------------------------------------------
  // Sections « Choisie pour vous » (Story 22.3).
  // ---------------------------------------------------------------------------

  /// Clé `sectionKey`-compatible d'une suggestion backend (`theme:`/`source:`).
  String _suggestionKey(TopTheme s) => s.kind == 'source' && s.sourceId != null
      ? tourneeSourceKey(s.sourceId!)
      : tourneeThemeKey(s.interestSlug);

  /// Suggestions « Choisie pour vous » réellement fetchables : filtre amont
  /// celles déjà masquées (dismiss) ou vivant en onglet Flâner — évite des
  /// round-trips inutiles.
  List<TopTheme> _usableSuggestions(List<TopTheme> suggestions) {
    final tournee = ref.read(tourneeOrderPrefsProvider);
    final flanerKeys = ref.read(tabOrderPrefsProvider).toSet();
    return [
      for (final s in suggestions)
        if (!tournee.hiddenKeys.contains(_suggestionKey(s)) &&
            !flanerKeys.contains(_suggestionKey(s)))
          s,
    ];
  }

  /// Construit la section d'une suggestion (`origin=="suggested"`) à partir de
  /// son `FeedResponse` déjà fetché. Réutilise les builders validés
  /// ([_buildSourceSection]/[_buildThemeSection]) en ne surchargeant que
  /// `origin`/`reason`. Une suggestion dont le feed du jour est **vide** est
  /// droppée (renvoie `null`) — jamais d'empty-state « Choisie pour vous » ;
  /// `isExplicitFavorite: true` empêche le builder thème de re-couper sous 2.
  FeedThemeSection? _buildSuggestedSection(
    TopTheme s,
    FeedResponse? feed,
    Map<String, Source> sourceById,
  ) {
    if ((feed?.items ?? const <Content>[]).isEmpty) return null;
    if (s.kind == 'source' && s.sourceId != null) {
      final src = sourceById[s.sourceId!];
      if (src == null) return null;
      return _buildSourceSection(
        feed: feed,
        source: src,
        origin: SectionOrigin.suggested,
        reason: s.reason,
      );
    }
    final visual = visualFor(s.interestSlug);
    return _buildThemeSection(
      feed: feed,
      label: visual.label,
      accent: visual.accent,
      isExplicitFavorite: true,
      themeSlug: s.interestSlug,
      origin: SectionOrigin.suggested,
      reason: s.reason,
    );
  }

  /// Fan-out **progressif et borné** des sections Tournée (Phase 2 du cold-open).
  ///
  /// Remplace l'ancien `Future.wait` global qui attendait les ~10 appels
  /// `personalized=true` d'un coup (sérialisés sous l'unique worker uvicorn →
  /// wall-clock d'ouverture plafonné par le timeout 8s, soit +10s ressentis).
  /// À la place :
  ///   - au plus [_kPhase2FanoutConcurrency] requêtes en vol (borne la charge
  ///     serveur et fait remonter les premières sections vite) ;
  ///   - les tâches partent dans l'ordre de rendu (thèmes → sources → veille →
  ///     suggérées), donc les sections au-dessus de la ligne de flottaison se
  ///     résolvent en premier ;
  ///   - [_compose] est émis dès qu'une section arrive (remplissage progressif)
  ///     au lieu d'un unique recompose final.
  ///
  /// Réutilise les fetch/build unitaires existants : `_fetchOneTheme` /
  /// `_fetchOneSource` + `_buildFavoriteThemeSection` / `_buildSourceSection` /
  /// `_buildSuggestedSection`. Les sections étant clés par `sectionKey` dans
  /// [_tourneeSectionByKey], l'ordre d'arrivée dans `_themes`/`_sources`/
  /// `_suggested` n'affecte pas l'ordre de rendu (fixé par `_orderedTourneeKeys`).
  Future<void> _fanOutSectionsProgressive({
    required List<FavoriteRef> favorites,
    required bool isExplicitFavorite,
    required List<SourceFavoriteRef> favoriteSources,
    required List<TopTheme> suggestions,
    required bool isSerene,
  }) async {
    final interestsState = _peekValue(userInterestsProvider);
    final catalog =
        _peekValue(userSourcesProvider) ?? const <Source>[];
    final sourceById = {for (final s in catalog) s.id: s};

    // Sources favorites résolues au catalogue (un favori absent du catalogue
    // est ignoré ce cycle, comme pour les coquilles seedées).
    final resolvedSources = <Source>[
      for (final fav in favoriteSources)
        if (sourceById[fav.sourceId] != null) sourceById[fav.sourceId]!,
    ];
    final usableSuggestions = _usableSuggestions(suggestions);

    void emit() => state = AsyncData(_compose(isSerene));

    // Squelette commun fetch→build→append→emit : seul varie le fetch, le
    // builder et la liste cible. `append` est invoqué uniquement si la section
    // est non-nulle ; l'émission est systématique (remplissage progressif).
    Future<void> sectionTask(
      Future<FeedResponse?> Function() fetch,
      FeedThemeSection? Function(FeedResponse? feed) build,
      void Function(FeedThemeSection section) append, {
      required String resolvedKey,
      void Function()? onEmpty,
    }) async {
      final section = build(await fetch());
      if (section != null) {
        append(section);
      } else {
        // Issue #1 — une suggestion résolue **vide** retire sa coquille seedée
        // (sinon un squelette « Choisie pour vous » resterait sans contenu). Un
        // léger shrink vers le bas seulement, jamais de pop vers le haut.
        onEmpty?.call();
      }
      // Fetch résolu (vide ou non) : la classification maigre/riche peut
      // désormais inspecter cette clé (cf. [_resolvedSectionKeys]).
      _resolvedSectionKeys.add(resolvedKey);
      emit();
    }

    // B3 — l'ordre de FETCH suit l'ordre de RENDU, plus l'ordre des favoris.
    // Les coquilles seedées rendent `sectionByKey` complet, donc
    // `_orderedTourneeKeys` (mêmes entrées que l'affichage : ordre manuel
    // sticky, biais « thème le plus suivi », ordre par score gelé du jour,
    // quota suggestions, cap) donne la position réelle de chaque section — les
    // sections au-dessus de la ligne de flottaison se résolvent en premier.
    final tournee = ref.read(tourneeOrderPrefsProvider);
    final renderedKeys = _orderedTourneeKeys(
      isSerene: isSerene,
      customized: tournee.customized,
      sectionByKey: _tourneeSectionByKey(),
      grilleAvailable: false,
      hiddenKeys: tournee.hiddenKeys,
      order: tournee.order,
      scoreOrder: _scoreOrderKeys,
    );
    final renderPos = <String, int>{
      for (var i = 0; i < renderedKeys.length; i++) renderedKeys[i]: i,
    };

    // B3 — suggestions réellement fetchées : celles du cap affiché, **+1 de
    // réserve** (ordre backend daily_rank) pour préserver la promesse de
    // `dismissSuggestion` — la suivante doit pouvoir remonter déjà remplie. Les
    // autres étaient fetchées puis jamais affichées (hors cap). Leurs coquilles
    // sont retirées : invisibles de toute façon (`_dropEmptySuggested`), mais
    // elles occuperaient un slot du quota suggestions avec une section vide.
    var suggestionReserveLeft = 1;
    final fetchedSuggestions = <TopTheme>[];
    for (final s in usableSuggestions) {
      if (renderPos.containsKey(_suggestionKey(s))) {
        fetchedSuggestions.add(s);
      } else if (suggestionReserveLeft-- > 0) {
        fetchedSuggestions.add(s);
      }
    }
    final droppedCount = usableSuggestions.length - fetchedSuggestions.length;
    if (droppedCount > 0) {
      final fetchedKeys = <String>{
        for (final s in fetchedSuggestions) _suggestionKey(s),
      };
      _suggested = [
        for (final s in _suggested)
          if (fetchedKeys.contains(sectionKey(s))) s,
      ];
    }

    final entries = <({String key, Future<void> Function() task})>[];
    // Thèmes / sujets / veille — tous fetchés quel que soit leur rang
    // (thin-classification, block scores, modale favoris en dépendent).
    for (final favRef in favorites) {
      final key = _favRefSectionKey(favRef);
      entries.add((
        key: key,
        task: () => sectionTask(
              () => _fetchOneTheme(favRef, isSerene),
              (feed) => _buildFavoriteThemeSection(
                favRef,
                feed,
                isExplicitFavorite: isExplicitFavorite,
                interestsState: interestsState,
              ),
              // Upsert par clé : remplace la coquille seedée à sa position
              // d'origine (ordre préservé) au lieu d'append (sinon doublon
              // coquille + contenu).
              (section) => _themes = _upsertByKey(_themes, section),
              resolvedKey: key,
            ),
      ));
    }
    // Sources favorites.
    for (final src in resolvedSources) {
      final key = tourneeSourceKey(src.id);
      entries.add((
        key: key,
        task: () => sectionTask(
              () => _fetchOneSource(src.id, isSerene),
              (feed) => _buildSourceSection(feed: feed, source: src),
              (section) => _sources = _upsertByKey(_sources, section),
              resolvedKey: key,
            ),
      ));
    }
    // Suggérées « Choisie pour vous » (hors classification maigre/riche, mais
    // marquées résolues sans effet — clé suggérée non favorite).
    for (final s in fetchedSuggestions) {
      final key = _suggestionKey(s);
      entries.add((
        key: key,
        task: () => sectionTask(
              () => (s.kind == 'source' && s.sourceId != null)
                  ? _fetchOneSource(s.sourceId!, isSerene)
                  : _fetchOneTheme(
                      ThemeFavoriteRef(slug: s.interestSlug),
                      isSerene,
                    ),
              (feed) => _buildSuggestedSection(s, feed, sourceById),
              // Upsert par clé : remplace la coquille suggérée seedée à sa
              // position (Issue #1) au lieu d'append (sinon doublon coquille +
              // contenu, et la coquille « poperait »).
              (section) => _suggested = _upsertByKey(_suggested, section),
              resolvedKey: key,
              onEmpty: () => _suggested = _removeByKey(_suggested, key),
            ),
      ));
    }
    // Tri unique par rang de rendu. Les clés hors de l'ordre affiché (favoris
    // masqués / au-delà du cap, réserve suggestion) prennent un rang de queue
    // dérivé de leur index d'origine (ordre relatif préservé, elles restent
    // fetchées) — sans dépendre de la stabilité de `List.sort` (non garantie).
    final rank = <String, int>{
      for (var i = 0; i < entries.length; i++)
        entries[i].key: renderPos[entries[i].key] ?? renderedKeys.length + i,
    };
    entries.sort((a, b) => rank[a.key]!.compareTo(rank[b.key]!));
    final tasks = [for (final e in entries) e.task];

    await _runWithConcurrency(tasks, _kPhase2FanoutConcurrency);
    _perfBoot('fanout_done_ms', ' tasks=${tasks.length} dropped=$droppedCount');
    // PR-4 — tout est stabilisé : le compose ci-dessous est le seul du jour à
    // (re)calculer l'ordre par score, et il l'applique dans la foulée.
    _freezeScoreOrderOnNextCompose = true;
    // Recompose final : garantit un état cohérent même si toutes les tâches
    // ont renvoyé une section nulle (rien émis dans la boucle).
    emit();
  }

  /// Remplace, dans [list], la section de même `sectionKey` que [section] par
  /// [section] **à sa position d'origine** ; l'ajoute en queue si absente. Le
  /// fan-out s'en sert pour substituer une coquille seedée par son contenu sans
  /// dupliquer la section ni déplacer son rang (l'ordre de la Tournée est dérivé
  /// de ce rang dans `_orderedTourneeKeys`).
  List<FeedThemeSection> _upsertByKey(
    List<FeedThemeSection> list,
    FeedThemeSection section,
  ) {
    final key = sectionKey(section);
    final idx = list.indexWhere((s) => sectionKey(s) == key);
    if (idx < 0) return [...list, section];
    final next = [...list];
    next[idx] = section;
    return next;
  }

  /// Retire de [list] la section de `sectionKey` == [key]. Issue #1 — une
  /// suggestion seedée mais résolue sans contenu disparaît après le fan-out.
  List<FeedThemeSection> _removeByKey(
          List<FeedThemeSection> list, String key) =>
      [
        for (final s in list)
          if (sectionKey(s) != key) s
      ];

  /// `true` ssi [list] contient déjà une section de même `sectionKey` que
  /// [section]. Sert aux chemins de refetch à n'upserter qu'une coquille encore
  /// présente (replace-only), pour ne pas réintroduire un favori retiré par un
  /// refetch concurrent.
  bool _hasSectionKey(List<FeedThemeSection> list, FeedThemeSection section) {
    final key = sectionKey(section);
    return list.any((s) => sectionKey(s) == key);
  }

  /// Exécute [tasks] avec au plus [maxConcurrent] en vol simultanément, en
  /// démarrant les tâches dans l'ordre fourni (les premières partent en
  /// premier — priorise les sections visibles). Ne lève jamais : chaque tâche
  /// borne déjà ses erreurs réseau via [_safe].
  Future<void> _runWithConcurrency(
    List<Future<void> Function()> tasks,
    int maxConcurrent,
  ) async {
    if (tasks.isEmpty) return;
    var next = 0;
    Future<void> worker() async {
      // `next++` est atomique ici : aucun `await` entre la lecture et
      // l'incrément (Dart mono-thread), donc deux workers ne prennent jamais
      // le même index.
      while (next < tasks.length) {
        final i = next++;
        await tasks[i]();
      }
    }

    final count = math.min(maxConcurrent, tasks.length);
    await Future.wait([for (var w = 0; w < count; w++) worker()]);
  }

  /// Retire une suggestion de la Tournée (dismiss). Mémoire **locale** via
  /// `hiddenKeys` (réversible, pas de pollution de l'algo global) ; le listener
  /// `tourneeOrderPrefsProvider` recompose et la suivante (si une suggestion
  /// avait été coupée par le cap) remonte gratuitement.
  Future<void> dismissSuggestion(FeedThemeSection section) async {
    final key = sectionKey(section);
    unawaited(
      ref.read(analyticsServiceProvider).trackSuggestionDismissed(
            sectionKey: key,
            kind: section.kind.name,
          ),
    );
    await ref.read(tourneeOrderPrefsProvider.notifier).setHidden(key, true);
  }

  /// Promeut une suggestion en favori dédié (réutilise le chemin favori
  /// existant). La section repassera `origin="validated"` au prochain load et
  /// sortira du pool suggéré. Les listeners `userInterests`/`userSources`
  /// recomposent la Tournée. [origin] (`card`/`sheet`, Story 22.6) trace le
  /// point d'entrée de la promotion pour l'analytics.
  Future<void> promoteSuggestion(
    FeedThemeSection section, {
    String origin = 'card',
  }) async {
    unawaited(
      ref.read(analyticsServiceProvider).trackSuggestionPromoted(
            sectionKey: sectionKey(section),
            kind: section.kind.name,
            origin: origin,
          ),
    );
    await ref.read(tourneeOrderPrefsProvider.notifier).markCustomized();
    try {
      if (section.kind == SectionKind.source && section.sourceId != null) {
        await ref.read(userSourcesStateProvider.notifier).setSourceState(
              section.sourceId!,
              InterestState.favorite,
              // Promotion = placement Essentiel : persiste le mode en DB.
              essentielMode: true,
            );
        await _appendTourneeOrder(tourneeSourceKey(section.sourceId!));
      } else if (section.themeSlug != null) {
        await ref.read(userInterestsProvider.notifier).setInterestState(
              ThemeFavoriteRef(slug: section.themeSlug!),
              InterestState.favorite,
              essentielMode: true,
            );
        await _appendTourneeOrder(tourneeThemeKey(section.themeSlug!));
      }
    } catch (e) {
      // Ne plus avaler l'échec : `setSourceState`/`setInterestState` ont
      // rollback leur état optimiste, l'ordre local n'a pas été touché ; on
      // propage pour que l'écran affiche une erreur au lieu d'un faux succès
      // (qui laissait une source « ajoutée » côté UI mais false en DB → évincée
      // au prochain cold boot).
      debugPrint('FluxContinu: promoteSuggestion failed: $e');
      rethrow;
    }
  }

  Future<void> _appendTourneeOrder(String key) async {
    final order = ref.read(tourneeOrderPrefsProvider).order;
    if (order.contains(key)) return;
    await ref
        .read(tourneeOrderPrefsProvider.notifier)
        .setOrder([...order, key]);
  }

  /// Story 22.7 — clés des sections dédiées à un **média** arrivées par la voie
  /// « Choisie pour vous ». Seules ces clés sont soustraites au tri par score
  /// (cf. [_freezeScoreOrder]) : les sources **favorites** (`_sources`, choix
  /// explicite de l'utilisateur) et les thèmes restent classés normalement.
  Set<String> get _suggestedSourceKeys => {
        for (final section in _suggested)
          if (section.kind == SectionKind.source) sectionKey(section),
      };

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
    final map = <String, FluxSection>{
      if (_actusDuJour != null) kTourneeActusKey: _actusDuJour!,
      if (_bonnes != null) kTourneeBonnesKey: _bonnes!,
      for (final section in _themes)
        if (!flanerThemeKeys.contains(sectionKey(section)))
          sectionKey(section): section,
      for (final section in _sources) sectionKey(section): section,
    };
    // Story 22.3 — sections suggérées : ajoutées seulement si la clé n'est pas
    // déjà prise par une validée (`putIfAbsent` ⇒ une validée l'emporte
    // toujours, p.ex. après une promotion) et pas routée vers Flâner.
    for (final section in _suggested) {
      final key = sectionKey(section);
      if (flanerThemeKeys.contains(key)) continue;
      map.putIfAbsent(key, () => section);
    }
    return map;
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
    // Blocs favoris à **déclasser** (curation pauvre du jour, cf.
    // [_poorFavoriteKeys]) : ils descendent sous les autres favoris sans jamais
    // passer sous une « Choisie pour vous ». Gelé à la journée comme
    // [scoreOrder] ⇒ vide pendant le fan-out.
    Set<String> poorKeys = const {},
    // PR-4 — ordre des blocs par score, **gelé pour la journée** (cf.
    // [_freezeScoreOrderIfNeeded]). Appliqué après l'ordre manuel (`applyOrder`,
    // qui reste la base et départage à score égal) et avant l'épingle Grille.
    // `null` ⇒ pas encore calculé (fan-out en cours) ou kill-switch off : ordre
    // par défaut inchangé.
    List<String>? scoreOrder,
    // `null` ⇒ aucun cap (passe de classification non cappée) ; sinon plafonne à
    // [cap] après réordonnancement (seul un surplus coupe les maigres dépriorisés).
    int? cap = kTourneeVisibleCap,
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
    // Tant que l'utilisateur n'a pas personnalisé l'ordre de sa Tournée, on
    // remonte en tête des thèmes celui auquel il a rattaché le plus de sujets
    // favoris (signal d'intérêt le plus fort, capté à l'onboarding). Un ordre
    // personnalisé (`customized`) est respecté tel quel par `applyOrder`.
    final orderedThemeKeys =
        customized ? themeKeys : _biasThemeKeysByMostFollowed(themeKeys);
    final favoriteKeys = [...orderedThemeKeys, ...sourceKeys, ...veilleKeys];
    // Story 22.3 — clés des sections « Choisie pour vous », best-first par
    // daily_rank (`_suggested` arrive déjà trié du backend). Insérées APRÈS les
    // validées (jamais devant) et dédupliquées contre elles : un compte
    // non-personnalisé les voit après ses favoris ; un compte personnalisé les
    // verra reléguées en fin par `applyOrder` (ordre manuel sticky) → coupées en
    // premier par le cap. Filtrées des `hiddenKeys` plus bas (dismiss respecté).
    final favoriteKeySet = favoriteKeys.toSet();
    final suggestedKeys = [
      for (final section in _suggested)
        if (sectionByKey.containsKey(sectionKey(section)) &&
            !favoriteKeySet.contains(sectionKey(section)))
          sectionKey(section),
    ];
    final suggestedKeySet = suggestedKeys.toSet();
    // Ordre par défaut unifié (normal & serein). Pour les comptes **non
    // personnalisés** (tous les nouveaux utilisateurs), on démarre la Tournée
    // par les Actus du jour — la section éditoriale cœur du rituel — puis les
    // favoris utilisateur (thèmes/sources/veille), puis les suggestions
    // « Choisie pour vous » (Story 22.3), puis Bonnes Nouvelles. La Grille
    // s'épingle juste après les Actus (plus bas) → 2ᵉ position par défaut.
    // Un compte **personnalisé** garde l'ordre historique (favoris d'abord,
    // Actus après) : `applyOrder` réapplique ensuite l'arrangement manuel
    // sticky à partir de cette base, laissant son comportement inchangé.
    // En mode serein ce sont les contenus serein qui peuplent ces mêmes
    // sections (fetch serein) ; seul l'ordre reste constant.
    // La Grille n'est PAS réordonnable par l'utilisateur (cf. modal « Mes
    // favoris ») : on l'exclut d'`applyOrder` et on l'épingle juste après les
    // Actus plus bas. Sinon, comme sa clé est absente de `order` (compte
    // personnalisé), `applyOrder` la reléguerait en fin de liste → coupée par
    // le cap → la Grille disparaîtrait. Régression corrigée par hotfix.
    final defaultKeys = <String>[
      if (!customized) kTourneeActusKey,
      ...favoriteKeys,
      ...suggestedKeys,
      if (customized) kTourneeActusKey,
      kTourneeBonnesKey,
    ];
    final availableKeys = [
      for (final key in defaultKeys)
        if (!hiddenKeys.contains(key) && sectionByKey.containsKey(key)) key,
    ];
    var ordered = applyOrder(availableKeys, order, (key) => key).toList();

    // PR-4 — tri par score du jour. Les clés non scorées (Actus, Bonnes, blocs
    // sans `recommendationReason`) gardent leur **position absolue** : c'est
    // exactement la sémantique de `mergeVisibleReorder`, réutilisée par
    // [applyScoreOrder] (`applyOrder` les aurait poussées en queue → coupées
    // par le cap).
    //
    // Bug « l'ordre des favoris ne se reflète pas dans la Tournée » : un bloc
    // que l'utilisateur a lui-même placé (clé présente dans `order`, l'ordre
    // qu'il compose dans « Mes favoris ») n'est plus déplacé par le tri du jour.
    // Son rang est un **choix**, pas une estimation — et comme l'ordre est gelé
    // à la journée, un réordre fait le soir ne se voyait pas avant le lendemain.
    // Le tri garde tout son rôle sur les blocs que l'utilisateur n'a PAS placés
    // (« Choisie pour vous », favori tout juste ajouté) : ils sont classés entre
    // eux, dans les slots que les blocs placés laissent libres.
    if (scoreOrder != null) {
      final placedByUser = order.toSet();
      ordered = applyScoreOrder(ordered, [
        for (final key in scoreOrder)
          if (!placedByUser.contains(key)) key,
      ]);
    }

    // Déclassement qualité (règle PO V1) — un bloc choisi dont la curation du
    // jour est pauvre ne disparaît pas : il descend simplement sous les autres
    // blocs choisis. Appliqué **après** l'ordre manuel et le tri du jour, sur
    // les seuls slots occupés par des blocs choisis ou suggérés : les cartes
    // éditoriales (Actus, Bonnes) gardent leur position absolue, comme sous
    // [applyScoreOrder].
    ordered = _demotePoorBlocks(
      ordered,
      poorKeys: poorKeys,
      favoriteKeys: favoriteKeySet,
      suggestedKeys: suggestedKeySet,
    );

    // Épingle la Grille immédiatement après les Actus du jour (ou en tête si
    // les Actus sont masqués/absents). C'est le seul point qui fixe la position
    // de la Grille — feed, sticky header (« Mot du jour ») et carte CTA en
    // dérivent tous via `grilleSlotIndex`.
    if (grilleAvailable && !hiddenKeys.contains(kTourneeGrilleKey)) {
      final actusIndex = ordered.indexOf(kTourneeActusKey);
      ordered.insert(actusIndex >= 0 ? actusIndex + 1 : 0, kTourneeGrilleKey);
    }

    if (cap == null || ordered.length <= cap) {
      return ordered.toList(growable: false);
    }

    // Bug « blocs favoris absents de l'Essentiel » — le cap ne coupe **jamais**
    // un bloc que l'utilisateur a placé dans son Essentiel (cartes éditoriales
    // + favoris thème/source/veille) au profit d'une « Choisie pour vous ».
    // Avant : `take(cap)` tranchait à l'aveugle et le quota 22.6 réservait des
    // slots aux suggestions **en évinçant des favoris** (`cap - quota`) ; comme
    // le tri par score du jour ([applyScoreOrder]) intercale suggestions et
    // favoris dans un même classement, un bloc explicitement choisi pouvait
    // passer sous le cap et disparaître — sans empty-state ni « Peu d'articles »,
    // donc indistinguable d'un bug pour l'utilisateur.
    //
    // Les suggestions restent un **accent quotidien** : elles n'occupent que les
    // slots laissés libres par les blocs choisis. L'esprit de la Story 22.6 (ne
    // pas voir *moins* de suggestions parce qu'on a personnalisé) tient toujours
    // dans le cas nominal — ≤ 7 favoris backend + 3 cartes éditoriales = 10 sur
    // 13 → il reste des slots ; seul un compte qui a lui-même rempli le cap de
    // blocs choisis n'a plus de place pour une suggestion.
    final chosenKeys = [
      for (final key in ordered)
        if (!suggestedKeySet.contains(key)) key,
    ];
    // Si l'utilisateur a lui-même plus de blocs que le cap, c'est la queue de
    // **son** ordre qui tombe — jamais un arbitrage de la Tournée.
    final keptChosen = chosenKeys.take(cap).toSet();
    final freeSlots = math.max(0, cap - keptChosen.length);
    final orderedSuggested = [
      for (final key in ordered)
        if (suggestedKeySet.contains(key)) key,
    ];
    final keptSuggested = orderedSuggested.take(freeSlots).toSet();

    // Ré-émission dans l'ordre d'affichage : le tri par score a pu intercaler
    // une suggestion entre deux favoris, on ne la relègue pas en queue.
    return [
      for (final key in ordered)
        if (keptChosen.contains(key) || keptSuggested.contains(key)) key,
    ].toList(growable: false);
  }

  /// Fait descendre les blocs de [poorKeys] sous les autres blocs choisis, sans
  /// jamais les faire passer sous une section « Choisie pour vous ».
  ///
  /// Ne redistribue que les slots déjà occupés par un bloc choisi ou suggéré :
  /// les cartes éditoriales (Actus, Bonnes) et tout ce qui n'est ni l'un ni
  /// l'autre gardent leur **position absolue** — même sémantique que
  /// [applyScoreOrder], sans quoi le déclassement d'un thème ferait glisser le
  /// rituel éditorial.
  ///
  /// No-op quand aucun bloc n'est pauvre : l'entrelacement favoris/suggestions
  /// produit par le tri du jour reste alors intact.
  List<String> _demotePoorBlocks(
    List<String> ordered, {
    required Set<String> poorKeys,
    required Set<String> favoriteKeys,
    required Set<String> suggestedKeys,
  }) {
    if (poorKeys.isEmpty) return ordered;

    final slots = <int>[];
    final healthy = <String>[];
    final poor = <String>[];
    final suggested = <String>[];
    for (var i = 0; i < ordered.length; i++) {
      final k = ordered[i];
      if (suggestedKeys.contains(k)) {
        slots.add(i);
        suggested.add(k);
      } else if (favoriteKeys.contains(k)) {
        slots.add(i);
        (poorKeys.contains(k) ? poor : healthy).add(k);
      }
    }
    if (poor.isEmpty) return ordered;

    final refilled = [...healthy, ...poor, ...suggested];
    final out = [...ordered];
    for (var i = 0; i < slots.length; i++) {
      out[slots[i]] = refilled[i];
    }
    return out;
  }

  /// Renvoie [themeKeys] avec, en tête, la clé du thème auquel l'utilisateur a
  /// rattaché le plus de **sujets favoris** (`customTopics` à l'état favori).
  /// No-op si < 2 thèmes, aucun sujet favori, ou si le thème dominant n'a pas de
  /// section thème rendue. N'est appelé que quand l'ordre n'est pas personnalisé.
  List<String> _biasThemeKeysByMostFollowed(List<String> themeKeys) {
    if (themeKeys.length < 2) return themeKeys;
    final interests = _peekValue(userInterestsProvider);
    if (interests == null) return themeKeys;

    final counts = <String, int>{};
    for (final t in interests.customTopics) {
      if (t.state != InterestState.favorite) continue;
      counts[t.slugParent] = (counts[t.slugParent] ?? 0) + 1;
    }
    if (counts.isEmpty) return themeKeys;

    String? topSlug;
    var topCount = 0;
    for (final entry in counts.entries) {
      if (entry.value > topCount) {
        topCount = entry.value;
        topSlug = entry.key;
      }
    }
    if (topSlug == null) return themeKeys;

    // slugParent → clé `theme:<slug>` de la section thème correspondante.
    String? topKey;
    for (final section in _themes) {
      if (section.kind == SectionKind.theme && section.themeSlug == topSlug) {
        topKey = sectionKey(section);
        break;
      }
    }
    if (topKey == null) return themeKeys;

    final idx = themeKeys.indexOf(topKey);
    if (idx <= 0) return themeKeys; // absent ou déjà en tête
    final reordered = [...themeKeys];
    reordered.removeAt(idx);
    reordered.insert(0, topKey);
    return reordered;
  }

  int? _resolveGrilleSlotIndex({
    required List<String> orderedKeys,
    required List<FluxSection> finalSections,
  }) {
    final grilleIndex = orderedKeys.indexOf(kTourneeGrilleKey);
    if (grilleIndex < 0) return null;
    final keysBeforeGrille = <String>{
      if (_essentiel != null) sectionKey(_essentiel!),
      // Comme le héros, le rappel d'alertes vit hors de `orderedKeys` et précède
      // toujours la Grille : sans lui, le slot serait décalé d'un cran vers le
      // haut les jours où une cloche a du neuf.
      kAlertsSectionKey,
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
  /// Saves the cost of refetching the digest, which doesn't depend on favorites.
  ///
  /// Même discipline que le fan-out de cold-open (**seed coquille → fetch →
  /// remplace en place**) : on seede d'abord les en-têtes pour [picked] en
  /// **conservant** le contenu déjà chargé (pas de clignotement contenu→vide sur
  /// un favori inchangé) — l'en-tête d'un favori **ajouté** apparaît donc tout de
  /// suite, un favori **retiré** disparaît, puis chaque section est remplacée par
  /// son contenu frais au fur et à mesure (`_fetchOneTheme` retry compris). Un
  /// fetch lent/raté laisse la coquille au lieu d'une section manquante.
  Future<void> _refetchThemesOnly(List<FavoriteRef> nextFavorites) async {
    final isSerene = ref.read(sereinToggleProvider).enabled;
    final picked = _pickExplicitFavorites(nextFavorites);
    _lastFavorites = picked;
    _themes = _reseedShells(_themes, _shellThemeSections(picked));
    if (state.valueOrNull != null) {
      state = AsyncData(_compose(isSerene));
    }
    final interestsState = _peekValue(userInterestsProvider);
    await _runWithConcurrency(
      [
        for (final favRef in picked)
          () async {
            final section = _buildFavoriteThemeSection(
              favRef,
              await _fetchOneTheme(favRef, isSerene),
              isExplicitFavorite: true,
              interestsState: interestsState,
            );
            // Remplace **uniquement** une coquille encore présente : si un
            // refetch concurrent a retiré ce favori entre-temps, on n'ajoute pas
            // sa section en retard (sinon un favori retiré clignote de retour).
            if (section != null && _hasSectionKey(_themes, section)) {
              _themes = _upsertByKey(_themes, section);
            }
            _resolvedSectionKeys.add(_favRefSectionKey(favRef));
            if (state.valueOrNull != null) {
              state = AsyncData(_compose(isSerene));
            }
          },
      ],
      _kPhase2FanoutConcurrency,
    );
  }

  /// Fusionne [freshShells] avec le contenu déjà chargé dans [existing] : pour
  /// chaque coquille fraîche (dans l'ordre des prefs), **conserve** la section de
  /// même `sectionKey` déjà présente, sinon garde la coquille. Évite le
  /// clignotement contenu→vide→contenu d'un reseed nu sur ajout/retrait d'un
  /// favori. Partagé par les reseeds thème ([_refetchThemesOnly]) et source
  /// ([_refetchSourcesOnly]).
  List<FeedThemeSection> _reseedShells(
    List<FeedThemeSection> existing,
    List<FeedThemeSection> freshShells,
  ) {
    final existingByKey = {for (final s in existing) sectionKey(s): s};
    return [
      for (final shell in freshShells)
        existingByKey[sectionKey(shell)] ?? shell,
    ];
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
  /// Même discipline progressive que [_refetchThemesOnly] (seed coquille en
  /// conservant le contenu chargé → fetch → remplace en place).
  Future<void> _refetchSourcesOnly(List<SourceFavoriteRef> picked) async {
    final isSerene = ref.read(sereinToggleProvider).enabled;
    _lastSourceFavorites = picked;
    // Race 2 (cf. [_ensureSourceCatalog]) : un refetch déclenché avant la
    // résolution du catalogue dropperait toutes les sections source.
    await _ensureSourceCatalog(picked);
    if (_disposed) return;
    _sources = _reseedShells(_sources, _shellSourceSections(picked));
    if (state.valueOrNull != null) {
      state = AsyncData(_compose(isSerene));
    }
    final catalog =
        _peekValue(userSourcesProvider) ?? const <Source>[];
    final sourceById = {for (final s in catalog) s.id: s};
    final resolved = <Source>[
      for (final fav in picked)
        if (sourceById[fav.sourceId] != null) sourceById[fav.sourceId]!,
    ];
    await _runWithConcurrency(
      [
        for (final src in resolved)
          () async {
            final section = _buildSourceSection(
              feed: await _fetchOneSource(src.id, isSerene),
              source: src,
            );
            // Replace-only (cf. [_refetchThemesOnly]) : ignore une source
            // retirée par un refetch concurrent pendant son fetch en vol.
            if (section != null && _hasSectionKey(_sources, section)) {
              _sources = _upsertByKey(_sources, section);
            }
            _resolvedSectionKeys.add(tourneeSourceKey(src.id));
            if (state.valueOrNull != null) {
              state = AsyncData(_compose(isSerene));
            }
          },
      ],
      _kPhase2FanoutConcurrency,
    );
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

  /// Wrap d'un fetch réseau **brut** (repo) avec retry borné des erreurs
  /// **transitoires**. Un `throw` (HTTP 5xx/401/timeout/déconnexion) est retryé
  /// jusqu'à [maxAttempts] avec un court [backoff] ; une réponse **200 même
  /// vide** ne **throw pas** → renvoyée telle quelle sans retry (un feed
  /// légitimement vide n'est pas une erreur). Renvoie `null` en dernier recours
  /// (comme [_safe]), donc les builders gèrent l'absence comme un état vide.
  ///
  /// Distinct de [_safe], qui ne sait pas distinguer « erreur » de « vide » et
  /// n'avale qu'une seule tentative : sous la charge sérialisée d'un fetch perso
  /// (unique worker uvicorn), un échec transitoire laissait sinon la section
  /// sous-remplie (0/1 carte) pour tout le cycle (bugs « Tournée figée » et
  /// « thème à 1 carte »).
  Future<T?> _fetchWithRetry<T>(
    Future<T?> Function() fn,
    String label, {
    int maxAttempts = 2,
    Duration backoff = const Duration(milliseconds: 250),
  }) async {
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await fn();
      } catch (e) {
        debugPrint(
            'FluxContinu: $label failed (attempt $attempt/$maxAttempts): $e');
        if (attempt >= maxAttempts) return null;
        await Future<void>.delayed(backoff);
      }
    }
    return null;
  }
}
