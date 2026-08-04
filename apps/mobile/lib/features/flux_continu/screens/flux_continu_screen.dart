import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart'
    show
        ValueListenable,
        defaultTargetPlatform,
        setEquals,
        TargetPlatform,
        visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:haptic_feedback/haptic_feedback.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:shimmer/shimmer.dart';
import 'package:visibility_detector/visibility_detector.dart';

import '../../../config/routes.dart';
import '../../../config/theme.dart';
import '../../../core/nudges/nudge_counters.dart';
import '../../../core/nudges/nudge_coordinator.dart';
import '../../../core/nudges/nudge_ids.dart';
import '../../../core/nudges/widgets/feed_nudge_anchors.dart';
import '../../../core/orchestration/first_impression_orchestrator.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/services/analytics_service.dart';
import '../../../core/providers/navigation_providers.dart';
import '../../../core/ui/notification_service.dart';
import '../../custom_topics/widgets/topic_chip.dart';
import '../../detail/content_preview_mapper.dart';
import '../../digest/models/digest_models.dart';
import '../../feed/models/content_model.dart';
import '../../feed/widgets/explore_section.dart' show ExploreDiscoverySkeleton;
import '../../feed/widgets/feedback_inline.dart';
import '../../feedback/widgets/call_invite_entry.dart';
import '../../feedback/widgets/feedback_closing_card.dart';
import '../../gamification/providers/streak_activity_provider.dart';
import '../../lettres/widgets/lettres_notification_banner.dart';
import '../../notif_du_jour/widgets/notif_du_jour_card.dart';
import '../../notifications/widgets/notification_activation_modal.dart';
import '../../onboarding/widgets/theme_choice_bottom_sheet.dart';
import '../../settings/widgets/display_mode_bottom_sheet.dart';
import '../../sources/models/source_theme_filters.dart';
import '../../tour/providers/guided_tour_controller.dart';
import '../../tour/tour_anchors.dart';
import '../../../shared/strings/loader_error_strings.dart';
import '../models/flux_continu_models.dart';
import '../providers/auto_grow_nudge_provider.dart';
import '../providers/edition_essentiel_provider.dart';
import '../providers/edition_read_status_provider.dart';
import '../providers/essentiel_triage_provider.dart';
import '../providers/flux_continu_provider.dart';
import '../providers/pending_feed_section_provider.dart';
import '../providers/personalisation_cta_provider.dart';
import '../providers/selected_edition_date_provider.dart';
import '../providers/tournee_order_prefs_provider.dart'
    show isTourneeReorderableKey, tourneeOrderPrefsProvider;
import '../providers/tournee_reorder_persistence.dart'
    show persistTourneeEssentielReorder, reorderTourneeTabKeys;
import '../services/preview_nudge_scheduler.dart';
import '../services/tournee_progress_service.dart'
    show TourneeProgressService;
import '../utils/morning_ritual_format.dart' show formatFrenchLongDate;
import '../utils/section_fit.dart'
    show
        kHeroLeadHeight,
        kHeroMediumHeight,
        kMinPlausibleUsableHeight,
        kTriageActionBarHeight,
        kTriageCardHeight,
        kTriageCounterHeight,
        kTriageProgressHeight,
        triageReservedHeight;
import '../utils/section_snap.dart';
import '../widgets/citation_du_jour_card.dart';
import '../widgets/closing_card_v18.dart';
import '../widgets/daily_completion_recap.dart';
import '../widgets/edition_timeline_sheet.dart';
import '../widgets/flux_continu_article_card.dart';
import '../widgets/my_interests_intro.dart';
import '../widgets/personalisation_cta_card.dart';
import '../widgets/tournee_composer_sheet.dart';
import '../widgets/section_banner.dart';
import '../widgets/section_block.dart';
import '../widgets/sticky_tab_bar.dart';
import '../widgets/suggestion_reason_sheet.dart';
import '../../grille/widgets/grille_cta_card.dart';

/// Scroll offset at which the AppBar is swapped with the sticky tab bar.
const double _kStickyThreshold = 60.0;

/// Vertical offset the sticky bar consumes — used as a landing buffer
/// when scrolling a section into view so its banner doesn't disappear
/// behind the bar. Trimmed 90 → 54 (head title dropped) then 54 → 50 after the
/// tabs row was compacted 48 → 44 (« cartes ≤ écran »): tabs row (44) + progress
/// track (4) + refresh strip (2). **Must mirror the real sticky bar height** —
/// it feeds the snap framing AND the fit budget ([usableViewportHeightProvider]).
const double _kStickyBarHeight = 50.0;

/// Flag one-shot du hint « maintiens un onglet pour réorganiser ta tournée ».
const String _kDragHintSeenKey = 'tournee_header_drag_hint_seen_v1';

/// px. Anti-crop safety inset for section-top snap anchors. Each snap `top` is
/// pulled up by this much so a section poses a hair **below** the sticky header
/// rather than flush — absorbing the small measurement jitter that
/// intermittently cropped a section's first line under the header. Kept minimal
/// (a few px): large enough to never crop, small enough to never reveal the
/// previous section. A *mitigation* — the real fix is measuring anchors on a
/// stabilised layout (gesture-start + post-fit recompute). Tune on device.
const double kSnapTopSafety = 4.0;

// Section-snap tuning lives in `utils/section_snap.dart` (kSnapCaptureFraction,
// kBoundaryCrossVelocity, kSnapEpsilon, kSnapSpring) so the resting-position
// arithmetic stays a pure, unit-testable function. The snap itself is woven
// into the fling's ballistic phase by [_SectionSnapPhysics] below.

/// Min depth (px) the user must reach before we surface the
/// pull-to-refresh hint pill — avoids nudging after a tiny inertia scroll.
const double _kPullHintMinDepthPx = 800.0;

/// Story 9.8 « L'Essentiel dynamique au retour » — cooldown avant qu'un retour
/// au premier plan ne rafraîchisse L'Essentiel.
///
/// Inspiré d'Instagram / LinkedIn : un aller-retour éclair (lire une notif,
/// copier un lien, basculer une seconde vers une autre app) ne DOIT pas
/// recharger le feed et coûter à l'utilisateur le fil de sa progression. Seul un
/// vrai « je reviens plus tard » (≥ ce délai) déclenche un refresh — et
/// uniquement quand l'utilisateur est en haut du feed (cf.
/// [shouldRefreshEssentielOnForeground]). Ce même délai borne l'intervalle
/// minimal entre deux refresh (anti-thrash sur des cycles background/foreground
/// rapprochés). Nettement plus court que le seuil widget Flâner (30 min) :
/// L'Essentiel est désormais la surface vivante, il doit se sentir « frais » au
/// retour sans jamais sursauter.
const Duration essentielForegroundRefreshCooldown = Duration(minutes: 2);

/// Décision pure du refresh au foreground de L'Essentiel. Retourne `true`
/// seulement si TOUT est vrai :
/// - [atTop] : l'utilisateur est en haut du feed Essentiel. Rafraîchir en cours
///   de lecture décalerait le contenu sous ses yeux → perte du fil ;
/// - [backgroundedFor] est connu ET ≥ [essentielForegroundRefreshCooldown] :
///   l'app est restée assez longtemps en arrière-plan (les bascules éclair ne
///   rechargent jamais — c'est le « cooldown » anti-toggle) ;
/// - [sinceLastRefresh] est `null` (jamais rafraîchi) OU ≥ le cooldown : pas de
///   refresh en rafale sur des reprises rapprochées.
///
/// Contrairement à [shouldRefreshFlanerOnForeground] (widget), un
/// [backgroundedFor] inconnu ne déclenche **pas** de refresh : on préfère un
/// faux négatif silencieux à un rechargement injustifié qui casserait la lecture.
@visibleForTesting
bool shouldRefreshEssentielOnForeground({
  required bool atTop,
  required Duration? backgroundedFor,
  required Duration? sinceLastRefresh,
}) {
  if (!atTop) return false;
  if (backgroundedFor == null ||
      backgroundedFor < essentielForegroundRefreshCooldown) {
    return false;
  }
  if (sinceLastRefresh != null &&
      sinceLastRefresh < essentielForegroundRefreshCooldown) {
    return false;
  }
  return true;
}

/// Un seul indicateur d'attente pour toute la Tournée : la **première** coquille
/// de section encore non résolue porte le libellé « Ta tournée se prépare… »
/// (les autres restent des cartes shimmer nues). `-1` = aucune coquille.
///
/// Extrait de `build` pour être testable sans monter l'écran (Supabase, Hive et
/// GoRouter y sont requis) : la déclaration inline avait été supprimée par
/// erreur lors d'une résolution de conflit, cassant tout build mobile.
@visibleForTesting
int firstPreparingSectionIndex(List<FluxSection> sections) =>
    sections.indexWhere((s) => s is FeedThemeSection && s.isPlaceholder);

/// Fenêtre pendant laquelle un **re-pull** explicite à vide compte comme « tout
/// de suite après » le précédent → escalade vers la redirection auto Flâner.
const Duration essentielRePullWindow = Duration(seconds: 45);

/// Escalade « rien de neuf » d'un pull-to-refresh explicite de L'Essentiel.
enum EssentielEmptyPullAction {
  /// Nouveauté, ou refresh borné/échoué : aucun hint, on reset l'escalade.
  none,

  /// 1er pull à vide : SnackBar + CTA « Flâner », pas de redirection.
  hint,

  /// Re-pull à vide rapproché (< [essentielRePullWindow]) : bascule auto Flâner.
  redirect,
}

/// Décision pure de l'escalade « rien de neuf » sur un pull-to-refresh
/// **explicite** (décidée avec le PO). Testable sans monter l'écran
/// (cf. [shouldRefreshEssentielOnForeground]).
///
/// - On n'escalade QUE sur un refresh réussi ET sans nouveauté : un refresh
///   borné/échoué (`succeeded == false`) ne redirige jamais — ce serait masquer
///   un souci de perf. Un `newSinceMorning > 0` remet l'escalade à zéro.
/// - Un 1er pull à vide → [EssentielEmptyPullAction.hint] ; un re-pull dans la
///   [rePullWindow] → [EssentielEmptyPullAction.redirect].
@visibleForTesting
EssentielEmptyPullAction essentielEmptyPullAction({
  required bool succeeded,
  required int newSinceMorning,
  required DateTime? lastEmptyPullAt,
  required DateTime now,
  Duration rePullWindow = essentielRePullWindow,
}) {
  if (!succeeded || newSinceMorning > 0) return EssentielEmptyPullAction.none;
  final repulledFast = lastEmptyPullAt != null &&
      now.difference(lastEmptyPullAt) <= rePullWindow;
  return repulledFast
      ? EssentielEmptyPullAction.redirect
      : EssentielEmptyPullAction.hint;
}

/// Comptabilité de la session Essentiel pour le garde-fou doomscroll (story
/// 9.8). Chrono **foreground** (suspendu en arrière-plan) + flag de complétion
/// de la carte de clôture, avec émission fire-once. Pur et à horloge injectée
/// (`now`) → testable sans monter l'écran (cf. `shouldRefreshEssentielOnForeground`).
@visibleForTesting
class DigestSessionTracker {
  Duration _elapsed = Duration.zero;
  DateTime? _foregroundSince;
  bool _closureAchieved = false;
  bool _emitted = false;

  bool get closureAchieved => _closureAchieved;
  bool get hasEmitted => _emitted;

  /// Démarre (ou redémarre) le chrono foreground à `now`.
  void start(DateTime now) => _foregroundSince = now;

  /// Suspend le chrono : verse l'intervalle courant dans le cumul. Idempotent
  /// (no-op si déjà suspendu) — le temps en arrière-plan ne compte jamais.
  void pause(DateTime now) {
    final since = _foregroundSince;
    if (since == null) return;
    _elapsed += now.difference(since);
    _foregroundSince = null;
  }

  /// Relance le chrono au retour au premier plan.
  void resume(DateTime now) => _foregroundSince = now;

  /// Marque la carte de clôture atteinte (fire-once implicite : idempotent).
  void markClosureSeen() => _closureAchieved = true;

  /// Durée foreground cumulée à `now`, sans muter l'état (pour l'inspection).
  Duration elapsedAt(DateTime now) {
    final since = _foregroundSince;
    return since == null ? _elapsed : _elapsed + now.difference(since);
  }

  /// Charge à émettre **une seule fois** (durée + clôture), ou `null` si déjà
  /// émise. Suspend le chrono au passage.
  ({int totalTimeSeconds, bool closureAchieved})? finish(DateTime now) {
    if (_emitted) return null;
    _emitted = true;
    pause(now);
    return (
      totalTimeSeconds: _elapsed.inSeconds,
      closureAchieved: _closureAchieved,
    );
  }
}

/// Onglets sticky des deux cartes virtuelles.
/// Accent intentionnellement neutre/crème (vs les accents vifs des sections
/// éditoriales) pour signaler visuellement que Grille et Citation sont du
/// contenu "pause / loisir" — le surligneur marker sera quasi discret.
const _kLeisureTabAccent = Color(0xFFB8A898);
const _motDuJourTab = StickyTab(
  label: 'Mot du jour',
  accent: _kLeisureTabAccent,
);
const _citationTab = StickyTab(
  label: 'Citation du jour',
  accent: _kLeisureTabAccent,
);
const _closingTab = StickyTab(
  label: 'Fin de tournée',
  accent: Color(0xFF2E7D32),
);
// Carte de personnalisation (virtuelle — pas de section correspondante).
const _persoCardTab = StickyTab(label: 'Pour toi', accent: Color(0xFFB0470A));

/// Signed *travel* direction from a [ScrollDirection]: +1 scrolling down (offset
/// increasing), -1 up, 0 idle/unknown. Shared mapping used by the snap physics
/// ([_SectionSnapPhysics._resolveTarget]) and the active-section tracking so
/// they can never disagree on « which way am I going ».
double _travelDirection(ScrollDirection d) => switch (d) {
      ScrollDirection.reverse => 1.0,
      ScrollDirection.forward => -1.0,
      ScrollDirection.idle => 0.0,
    };

class FluxContinuScreen extends ConsumerStatefulWidget {
  const FluxContinuScreen({super.key});

  @override
  ConsumerState<FluxContinuScreen> createState() => _FluxContinuScreenState();
}

class _FluxContinuScreenState extends ConsumerState<FluxContinuScreen>
    with WidgetsBindingObserver {
  final ScrollController _scroll = ScrollController();

  /// Contrôleur dédié au mode « édition passée » (sélecteur de date). Séparé du
  /// `_scroll` live (snap + sticky) : leurs CustomScrollView s'excluent, et un
  /// contrôleur dédié évite tout conflit d'attachement et préserve la position
  /// du feed live quand on revient à « Aujourd'hui ».
  final ScrollController _editionScroll = ScrollController();
  final ScrollController _tabsScroll = ScrollController();
  final ValueNotifier<bool> _stickyVisible = ValueNotifier(false);
  final ValueNotifier<int> _activeIndex = ValueNotifier(0);

  /// Guards the section haptic to **one buzz per gesture**. The haptic is now
  /// fired at snap *commit* — the instant the fling engages a spring toward a
  /// *different* section ([_SectionSnapPhysics.onSnapCommit]) — so it precedes
  /// the pose animation instead of trailing it at settle («&nbsp;trop tard&nbsp;»).
  /// Reset on `ScrollStartNotification`. A drag-then-snapback commits back to
  /// the origin section (target index == active index) → no buzz.
  bool _snapHapticFiredThisGesture = false;

  final List<GlobalKey> _sectionKeys = [];

  // Clés dédiées aux cartes virtuelles qui ont désormais un onglet sticky.
  // La Grille n'est montée qu'à un seul endroit à la fois (après Actus, ou en
  // fallback bas) → une seule clé suffit. Disjointes de [_sectionKeys] : le
  // suivi de section active (qui itère _sectionKeys) reste inchangé.
  final GlobalKey _grilleKey = GlobalKey();
  final GlobalKey _citationKey = GlobalKey();
  final GlobalKey _closingKey = GlobalKey();
  final GlobalKey _persoCardKey = GlobalKey();

  // Clés des « entrées sticky » dans l'ordre exact des slivers : sections +
  // Mot du jour + Citation + Fin de tournée. Source unique pour le suivi de
  // section active et le scroll-to-section (les onglets en dérivent via
  // [_syncStickyEntries]).
  final List<GlobalKey> _stickyEntryKeys = [];

  /// Derniers descripteurs d'onglets produits par [_syncStickyEntries], alignés
  /// sur [_stickyEntryKeys]. Sert de référentiel au remappage index → clé
  /// d'ordre lors d'un réordre par drag ([_onHeaderReorder]).
  List<StickyTab> _stickyTabs = const [];

  /// Un onglet du header est soulevé. Gèle l'auto-align de la rangée et le
  /// suivi de section active : sans ça, un scroll résiduel recentrerait les
  /// onglets sous le doigt en plein drag.
  bool _headerDragging = false;

  /// Sliver « Grille du jour » (carte d'entrée de La Grille). Son insertion est
  /// pilotée par `FluxContinuState.grilleSlotIndex`. Wrappé dans un
  /// `KeyedSubtree(_grilleKey)` pour exposer la carte au suivi sticky.
  ///
  /// [followedByNormalSection] : true en mi-feed (la carte suivante n'a pas de
  /// marge top propre, donc le bottom padding ici recrée l'écart standard
  /// inter-sections) ; false en fin de feed (suivie de `CitationDuJourCard`,
  /// qui porte déjà 24px de marge top — un bottom padding ici doublerait
  /// l'écart, jugé incorrect par le PO).
  SliverToBoxAdapter _grilleSliver({required bool followedByNormalSection}) =>
      SliverToBoxAdapter(
        child: KeyedSubtree(
          key: _grilleKey,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              16,
              22,
              16,
              followedByNormalSection ? 16 : 0,
            ),
            child: const GrilleCtaCard(),
          ),
        ),
      );

  /// Articles swipe-dismissed and replaced by a [FeedbackInline] banner at
  /// the same position. The hide API has already fired (via
  /// `markHiddenRemote`); resolution (chip / X / undo) drives
  /// `confirmDismiss` or `undoHide` on the provider.
  final Set<String> _pendingFeedback = <String>{};
  bool _gestureNudgeRequested = false;
  bool _showSwipeHint = false;

  /// Story 22.6 — garde-fou mémoire : sections suggérées déjà comptées en
  /// impression durant la vie de cet écran. Évite de relire SharedPreferences à
  /// chaque rebuild ; la dédup **persistée** (1×/section/jour) reste dans
  /// `AnalyticsService.trackSuggestionImpression`.
  final Set<String> _impressedSuggestionKeys = <String>{};

  /// Mutable, stable holder of the section-start anchors (absolute scroll
  /// pixels). Passed *by reference* to the immutable [_SectionSnapPhysics],
  /// which reads it live — the physics is rebuilt every frame and must never
  /// own a copy. Recomputed only on layout/content changes (sections don't
  /// resize mid-session), never per scroll frame.
  final _SnapAnchors _snapAnchors = _SnapAnchors();
  bool _snapAnchorsRecomputeScheduled = false;

  /// (A3) Indices (into `state.sections`) of sections taller than the viewport —
  /// the ones with a free-reading interior (`bottom > top`, same predicate as
  /// the physics' free zone). Drives the [_FreeReadEdgeFade] « lecture libre »
  /// signifier. Rebuilt in [_recomputeSnapAnchors].
  final ValueNotifier<Set<int>> _tallSections = ValueNotifier(const {});

  /// Total bottom overlay height (app nav bar + system insets), captured from
  /// [MediaQuery.paddingOf] in [build]. With [extendBody: true] on the outer
  /// Scaffold, padding.bottom reflects the actual rendered height of
  /// [MainBottomNav] (50 dp content + SafeArea bottom padding), so it adapts
  /// automatically when the Android navigation bar raises the footer.
  /// Read in [_recomputeSnapAnchors] (post-frame callback — direct MediaQuery
  /// reads are unsafe there).
  double _safeAreaBottom = 0;

  /// Garde-fou : le flow post-onboarding (dialog customs échoués + modales
  /// thème & notifications) ne doit se jouer qu'une seule fois par montage,
  /// jamais sur un refetch/scroll/rebuild.
  bool _postOnboardingFlowRan = false;

  /// Garde-fou : un seul cycle de consommation du deep-link « file droit vers
  /// une section » (cf. [pendingFeedSectionKeyProvider]) est planifié à la fois
  /// — pas un par rebuild tant que la clé n'est pas résolue.
  bool _pendingSectionConsumeScheduled = false;

  // Pull-to-refresh discoverability pill. Shown briefly when the user
  // scrolls back to the top after having browsed deep enough (>=
  // [_kPullHintMinDepthPx]) so the gesture is signalled without being
  // mandatory. Throttled to once every ~2 minutes.
  bool _showPullHint = false;
  double _maxScrollDepthPx = 0;
  DateTime? _lastPullHintAt;
  Timer? _pullHintTimer;

  // Hint one-shot « maintiens un onglet pour réorganiser ». Affiché à la 1ʳᵉ
  // révélation du header sticky comportant au moins deux onglets déplaçables,
  // puis jamais plus (flag SharedPreferences). Rendu en overlay sous la barre
  // sticky, donc sans impact sur `_kStickyBarHeight` ni sur les budgets de fit.
  bool _showDragHint = false;

  /// Pessimiste tant que les prefs ne sont pas lues : pas de hint sur un cold
  /// boot où l'utilisateur l'a déjà vu.
  bool _dragHintSeen = true;
  Timer? _dragHintTimer;

  /// Story 9.8 — horodatages du dernier passage en arrière-plan et du dernier
  /// refresh au foreground, pour le cooldown anti-refresh-intempestif
  /// (cf. [shouldRefreshEssentielOnForeground]).
  DateTime? _backgroundedAt;
  DateTime? _lastForegroundRefreshAt;

  /// Escalade « rien de neuf » → Flâner (décidée avec le PO). Horodatage du
  /// dernier pull explicite à vide : un 1er pull à vide affiche un SnackBar +
  /// CTA « Flâner », un **re-pull** rapproché (dans [essentielRePullWindow])
  /// bascule automatiquement vers l'onglet Flâner. Un refresh avec nouveauté ou
  /// borné/échoué le remet à `null`. L'auto-redirect ne se déclenche jamais sur
  /// le refresh foreground (réservé au geste explicite).
  DateTime? _lastEmptyPullAt;

  /// Story 9.8 — instrumentation « garde-fou doomscroll ». Durée foreground de
  /// la session Essentiel + complétion de la carte de clôture, émises une fois
  /// via `trackDigestSession` au [dispose]. Toute la comptabilité vit dans
  /// [DigestSessionTracker] (pur, testable).
  final DigestSessionTracker _sessionTracker = DigestSessionTracker();
  int _lastKnownStreak = 0;

  /// Service analytics capturé au montage : `dispose()` émet la session digest,
  /// mais en fin de teardown `ref` n'est plus lisible (« Cannot use ref after
  /// the widget was disposed »). Lire ici, au montage, où `ref` est valide,
  /// évite que `_emitDigestSession` ne jette et n'interrompe le reste du
  /// démontage (annulation des timers → « Timer still pending »).
  late final AnalyticsService _analytics;

  // Nudge auto-grow « découvre l'aperçu au long-press » : un pulse discret sur
  // une carte visible + non lue, quelques fois par jour, tant que l'utilisateur
  // n'a pas fait un vrai long-press (cf. preview_nudge_scheduler.dart).
  Timer? _autoGrowTimer;
  int _autoGrowNonce = 0;
  final math.Random _autoGrowRng = math.Random();

  /// Premier paint : on force le squelette (cartes vides à en-têtes réels) pour
  /// la toute première frame, **même si les données sont déjà prêtes**. À
  /// l'arrivée depuis le rituel matinal, l'édition est préchargée → l'écran
  /// ferait sinon directement le premier paint *lourd* de `_buildContent`, qui
  /// bloque ~1 s sur le web : on verrait une page blanche (la frame précédente).
  /// En peignant d'abord le squelette (cheap), la frame lourde se construit
  /// *derrière* tandis que le squelette reste à l'écran — zéro blanc. La branche
  /// Essentiel vit dans un `StatefulShellBranch` gardé en vie : cet écran n'est
  /// monté qu'une fois par session, donc aucun flash de squelette sur les
  /// bascules d'onglet ultérieures.
  bool _firstPaintDone = false;

  @override
  void initState() {
    super.initState();
    // Capture le service analytics tant que `ref` est valide (cf. _analytics).
    _analytics = ref.read(analyticsServiceProvider);
    // Observe le cycle de vie pour ré-actualiser L'Essentiel au retour au
    // premier plan (story 9.8, cf. [didChangeAppLifecycleState]).
    WidgetsBinding.instance.addObserver(this);
    _scroll.addListener(_onScroll);
    // Compte une ouverture du feed par montage de l'écran. Alimente la bannière
    // de demande de géoloc (déclenchée après 5 ouvertures, cf.
    // geoloc_prompt_provider). Best-effort, n'impacte pas le rendu.
    unawaited(NudgeCounters.increment(NudgeCounters.feedOpenCount));
    // Bascule vers le vrai contenu après la 1ʳᵉ frame (squelette peint → la
    // frame lourde se construit ensuite, squelette toujours visible).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _firstPaintDone = true);
    });
    // Démarre le chrono de session Essentiel (garde-fou doomscroll, story 9.8).
    _sessionTracker.start(DateTime.now());
    // Tick régulier du nudge auto-grow. Léger : ne fait rien tant qu'aucune
    // carte n'est visible ou que le scheduler refuse (budget/espacement/déjà
    // découvert).
    _autoGrowTimer = Timer.periodic(
      const Duration(seconds: 60),
      (_) => unawaited(_maybeTriggerAutoGrow()),
    );
    unawaited(_loadDragHintSeen());
  }

  Future<void> _loadDragHintSeen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) return;
      _dragHintSeen = prefs.getBool(_kDragHintSeenKey) ?? false;
    } catch (_) {
      // Pas de prefs (tests sans mock) → on reste silencieux.
    }
  }

  /// Révèle une fois le hint de réorganisation, si le header expose au moins
  /// deux onglets déplaçables. Marque le flag immédiatement (avant l'écriture
  /// asynchrone) pour ne jamais le montrer deux fois dans la même session.
  void _maybeShowDragHint() {
    if (_dragHintSeen || _showDragHint) return;
    if (!stickyTabsAllowReorder(_stickyTabs)) return;
    _dragHintSeen = true;
    unawaited(
      SharedPreferences.getInstance()
          .then((prefs) => prefs.setBool(_kDragHintSeenKey, true))
          .catchError((Object _) => false),
    );
    setState(() => _showDragHint = true);
    _dragHintTimer?.cancel();
    _dragHintTimer = Timer(const Duration(milliseconds: 2400), () {
      if (mounted) setState(() => _showDragHint = false);
    });
  }

  @override
  void dispose() {
    // Émet la session digest avant de démonter (ref encore valide).
    _emitDigestSession();
    WidgetsBinding.instance.removeObserver(this);
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    _editionScroll.dispose();
    _tabsScroll.dispose();
    _stickyVisible.dispose();
    _activeIndex.dispose();
    _tallSections.dispose();
    _pullHintTimer?.cancel();
    _dragHintTimer?.cancel();
    _autoGrowTimer?.cancel();
    super.dispose();
  }

  /// Déclenche au plus un pulse auto-grow : tire une carte visible + non lue au
  /// hasard si le scheduler l'autorise. Sans candidat visible (écran masqué en
  /// IndexedStack, ou tout est lu) → no-op.
  Future<void> _maybeTriggerAutoGrow() async {
    if (!mounted) return;
    if (ref.read(visibleFluxContentIdsProvider).isEmpty) return;
    final scheduler = ref.read(autoGrowNudgeSchedulerProvider);
    if (!await scheduler.canTriggerNow()) return;
    if (!mounted) return;
    // Re-lit après l'await : le set visible a pu changer entre-temps.
    final candidates = ref.read(visibleFluxContentIdsProvider).toList();
    if (candidates.isEmpty) return;
    final pick = candidates[_autoGrowRng.nextInt(candidates.length)];
    _autoGrowNonce++;
    ref.read(autoGrowNudgeSignalProvider.notifier).state =
        AutoGrowSignal(contentId: pick, nonce: _autoGrowNonce);
    await scheduler.recordTriggered();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    final currentScroll = pos.pixels;
    final showSticky = currentScroll > _kStickyThreshold;
    if (_stickyVisible.value != showSticky) {
      _stickyVisible.value = showSticky;
      if (showSticky) _maybeShowDragHint();
    }
    _updateActiveSection();

    if (currentScroll > _maxScrollDepthPx) {
      _maxScrollDepthPx = currentScroll;
    }

    // Footer auto-hide (app-wide) : ne se cache QUE sur un scroll-down
    // utilisateur réel. On lit `userScrollDirection` (et non un delta de
    // position) car le snap est une activité balistique qui conserve la
    // dernière direction utilisateur : un settle qui ré-ajuste la carte vers le
    // bas après un scroll-up reste `forward` → le footer ne disparaît jamais
    // tant que l'utilisateur n'a pas effectivement scrollé vers le bas. `idle`
    // (settle terminé / programmatique) ne touche pas à la visibilité.
    if (currentScroll < _kStickyThreshold) {
      updateFooterVisibility(ref, true);
    } else if (pos.userScrollDirection == ScrollDirection.reverse) {
      updateFooterVisibility(ref, false);
    } else if (pos.userScrollDirection == ScrollDirection.forward) {
      updateFooterVisibility(ref, true);
    }

    // Pull-to-refresh hint pill — discoverability cue when the user scrolls
    // back to the very top after browsing deep. Never triggers a refresh.
    final scrollingUp = pos.userScrollDirection == ScrollDirection.forward;
    if (scrollingUp &&
        currentScroll < 20 &&
        _maxScrollDepthPx >= _kPullHintMinDepthPx) {
      final now = DateTime.now();
      final last = _lastPullHintAt;
      if (last == null || now.difference(last) > const Duration(minutes: 2)) {
        _lastPullHintAt = now;
        setState(() => _showPullHint = true);
        _pullHintTimer?.cancel();
        _pullHintTimer = Timer(const Duration(milliseconds: 1800), () {
          if (mounted) setState(() => _showPullHint = false);
        });
      }
    }
  }

  void _updateActiveSection() {
    if (_stickyEntryKeys.isEmpty) return;
    if (_headerDragging) return;
    // Active = sticky entry that occupies the most visible area below the
    // sticky bar. The previous heuristic ("last section whose top has crossed
    // stickyBar + 200px lookahead") switched late on long sections because it
    // ignored how much of the upcoming section was already on screen. Viewport
    // dominance flips the active tab as soon as the next entry becomes
    // majority-visible, which matches what the user is actually reading. Itère
    // la liste combinée (sections + Mot du jour + Citation).
    const viewportTop = _kStickyBarHeight;
    final viewportBottom = viewportTop +
        (_scroll.hasClients ? _scroll.position.viewportDimension : 0.0);
    int activeAt = 0;
    double bestVisible = -1;
    for (var i = 0; i < _stickyEntryKeys.length; i++) {
      final ctx = _stickyEntryKeys[i].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox) continue;
      final top = box.localToGlobal(Offset.zero).dy;
      final bottom = top + box.size.height;
      final clampedTop = top.clamp(viewportTop, viewportBottom);
      final clampedBottom = bottom.clamp(viewportTop, viewportBottom);
      final visible = clampedBottom - clampedTop;
      if (visible > bestVisible) {
        bestVisible = visible;
        activeAt = i;
      }
    }
    if (_activeIndex.value != activeAt) {
      // Visual-only tab tracking here. The section haptic used to fire on this
      // per-frame flip, which double-buzzed a drag-then-snapback (flip N→N+1
      // mid-drag, then N+1→N on the pull-back). It now fires once at settle —
      // see `_onScrollNotification` (`ScrollEndNotification`), gated on a real
      // change of section across the whole gesture.
      _activeIndex.value = activeAt;
      _alignTabsToActive(activeAt);
    }
  }

  int _sectionIndexForStickyIndex(int stickyIndex) {
    if (stickyIndex < 0 || stickyIndex >= _stickyEntryKeys.length) return -1;
    final key = _stickyEntryKeys[stickyIndex];
    for (var i = 0; i < _sectionKeys.length; i++) {
      if (identical(_sectionKeys[i], key)) return i;
    }
    return -1;
  }

  /// Fires when a scroll gesture *starts*. Refreshes the snap anchors so the
  /// ballistic that follows reads frames measured on the current, settled
  /// layout — not stale ones from before the fit converged (a source of the
  /// intermittent top-crop). Post-frame + coalesced, so it never runs per
  /// frame. Returns `false` to let the notification bubble.
  bool _onScrollNotification(ScrollNotification n) {
    if (n is ScrollStartNotification) {
      _scheduleAnchorRecompute();
      // New gesture → re-arm the section haptic. It fires at snap commit
      // (`_onSnapCommit`), not at settle.
      _snapHapticFiredThisGesture = false;
    }
    return false;
  }

  /// Called by [_SectionSnapPhysics] the instant a fling commits a snap toward
  /// [committedTarget] (finger lift), *before* the pose animation runs. Fires a
  /// single crisp haptic when — and only when — the target frames a *different*
  /// section than the one currently active. This lands the buzz at the moment
  /// of passage (leads the animation → « réactif ») instead of at settle.
  ///
  /// Gated so it stays silent on:
  /// - the initial top-of-page scroll (sticky bar hidden);
  /// - a `top → bottom` re-frame inside the same tall section (same index);
  /// - a deadband pull-back to the origin section (target index == active);
  /// - repeat `createBallisticSimulation` calls within one gesture
  ///   ([_snapHapticFiredThisGesture]).
  void _onSnapCommit(double committedTarget) {
    if (_snapHapticFiredThisGesture || !_stickyVisible.value) return;
    final targetIndex = frameIndexOfTarget(_snapAnchors.values, committedTarget);
    if (targetIndex < 0 || targetIndex == _activeIndex.value) return;
    _snapHapticFiredThisGesture = true;
    unawaited(_triggerSectionChangeHaptic());
  }

  Future<void> _triggerSectionChangeHaptic() async {
    try {
      // `rigid` = a sharp, dense single click (Android PRIMITIVE_CLICK ~34ms /
      // iOS rigid style) — marks the exact moment of passage. `heavy` was a
      // diffuse THUD that felt weak and « étalée ».
      await Haptics.vibrate(HapticsType.rigid, usage: HapticsUsage.touch);
    } catch (_) {
      await HapticFeedback.mediumImpact();
    }
  }

  /// Recomputes the section framing offsets from current layout. Each sticky
  /// entry yields a [SectionFrame]:
  /// - `top`    : the offset that brings the entry's top flush under the sticky
  ///   bar (identical maths to [_scrollToSection]);
  /// - `bottom` : the offset that brings the entry's bottom flush to the footer.
  ///   It is `> top` only for entries taller than the usable viewport — those
  ///   get a free-reading interior; shorter entries collapse `bottom == top`.
  ///
  /// [resolveSnapTarget] turns these into the edge-triggered feel: free while a
  /// section fills the screen, snap to the next frame in the travel direction
  /// otherwise. Offset-invariant (we add `_scroll.offset` back), so it is safe
  /// to run mid-scroll.
  void _recomputeSnapAnchors() {
    if (!_scroll.hasClients) {
      _snapAnchors.values = const [];
      _tallSections.value = const {};
      return;
    }
    final scrollBox = _scroll.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (scrollBox == null) return;
    final offset = _scroll.offset;
    // Visible bottom edge: the scroll area extends under the shared footer
    // (content passes beneath it), so the section bottom must land above the
    // footer bar + bottom safe-area, else the last cards (« Lire plus ») are
    // truncated.
    final visibleBottom = scrollBox.size.height - _safeAreaBottom;
    // « Estimer pour contrôler, mesurer pour vérifier » : on publie le budget
    // de hauteur utile (identique à la frontière tall/free du snap ci-dessous)
    // pour que le provider décide combien d'articles tiennent. Anti-boucle :
    // écriture seulement si la valeur arrondie change.
    _publishUsableHeight(visibleBottom - _kStickyBarHeight);
    final result = <SectionFrame>[];
    final tall = <int>{};
    // Measured global top of the currently-active sticky entry — captured for
    // the debug crop detector below.
    double? activeTopGlobal;
    for (var k = 0; k < _stickyEntryKeys.length; k++) {
      final ctx = _stickyEntryKeys[k].currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject();
      if (box is! RenderBox || !box.attached) continue;
      final topGlobal = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy;
      if (k == _activeIndex.value) activeTopGlobal = topGlobal;
      // Anti-crop safety inset ([kSnapTopSafety]): pose the section a hair below
      // the header instead of flush, absorbing measurement jitter that would
      // otherwise crop its first line under the sticky bar.
      final top = offset + (topGlobal - _kStickyBarHeight) - kSnapTopSafety;
      // Bottom flush to the visible bottom (above the footer). `bottom - top =
      // sectionHeight - usableViewport`, so `bottom > top` exactly when the
      // section is taller than the visible area — i.e. only those gain a
      // free-reading zone.
      final bottom = offset + (topGlobal + box.size.height) - visibleBottom;
      result.add((top: top, bottom: bottom));
      // Map this entry to its real section index (virtual cards ⇒ −1) for the
      // A3 free-read fade.
      final sectionIndex = _sectionIndexForStickyIndex(k);
      if (sectionIndex >= 0 && bottom > top + kSnapEpsilon) {
        tall.add(sectionIndex);
      }
    }
    result.sort((a, b) => a.top.compareTo(b.top));
    _snapAnchors.values = result;
    if (!setEquals(_tallSections.value, tall)) {
      _tallSections.value = tall;
    }
    // Filet de vérification (pas de pilotage), debug only :
    // 1) toute section multi-articles qui reste « tall » malgré le fit côté
    //    provider — symptôme d'une estimation `section_fit` trop généreuse.
    // 2) **détecteur de crop** : la section active dont le haut mesuré est passé
    //    au-dessus du header (topGlobal < barre sticky) — le signal reproductible
    //    qu'on cherchait pour caler [kSnapTopSafety] et le durcissement du calcul.
    assert(() {
      final sections = ref.read(fluxContinuProvider).valueOrNull?.sections;
      if (sections != null) {
        for (final idx in tall) {
          if (idx < 0 || idx >= sections.length) continue;
          debugPrint(
            '[fit-net] section "${sections[idx].label}" dépasse l\'écran '
            '(reste tall) — estimation section_fit trop généreuse, à régler.',
          );
        }
      }
      if (activeTopGlobal != null &&
          activeTopGlobal < _kStickyBarHeight - kSnapTopSafety - kSnapEpsilon) {
        debugPrint(
          '[fit-net] CROP — section active haut mesuré à '
          '${activeTopGlobal.toStringAsFixed(1)}px < header '
          '($_kStickyBarHeight) : le haut passe sous le sticky bar '
          '(mesure sur layout non stabilisé — durcir le recompute).',
        );
      }
      return true;
    }());
  }

  /// Threads the measured usable scroll height to [usableViewportHeightProvider]
  /// so the provider can decide how many articles each section may show. Same
  /// budget the snap uses (viewport − safe-area-bottom − sticky bar). Anti-boucle :
  /// only writes when the rounded value actually moves, so the provider recompose
  /// it triggers (→ screen rebuild → this runs again, same value) terminates.
  void _publishUsableHeight(double height) {
    // Rejet à la source des mesures aberrantes/transitoires (render box détachée
    // / recompose hors-écran lors d'un changement de mode) : sous le plancher de
    // plausibilité, on NE publie PAS — la dernière bonne hauteur reste en place
    // et le provider ne bascule pas sur un fallback. (kMinPlausibleUsableHeight
    // ≈ 360, bien sous les ~480px utiles du plus petit téléphone.)
    if (height < kMinPlausibleUsableHeight) return;
    final rounded = height.roundToDouble();
    final notifier = ref.read(usableViewportHeightProvider.notifier);
    final current = notifier.state;
    if (current != null && (current - rounded).abs() < 1.0) return;
    notifier.state = rounded;
    // The published budget just moved ⇒ the provider will recompute how many
    // cards each section shows, changing section heights. Schedule a fresh
    // anchor recompute so the frames reflect the *final* card count, not the
    // transient one measured here. Coalesced + idempotent: once the height
    // stabilises this early-returns above, so the loop terminates.
    _scheduleAnchorRecompute();
  }

  /// Defers an anchor recompute to the next post-frame (when layout is settled),
  /// coalescing the bursts of builds that "Plus de…"/content changes produce
  /// into a single pass. Never runs per scroll frame.
  void _scheduleAnchorRecompute() {
    if (_snapAnchorsRecomputeScheduled) return;
    _snapAnchorsRecomputeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _snapAnchorsRecomputeScheduled = false;
      if (!mounted) return;
      _recomputeSnapAnchors();
    });
  }

  void _alignTabsToActive(int index) {
    // Gelé pendant un drag d'onglet : l'auto-align se battrait avec
    // l'auto-scroll aux bords du `ReorderableListView`.
    if (_headerDragging) return;
    if (!_tabsScroll.hasClients) return;
    void doScroll() {
      if (!_tabsScroll.hasClients) return;
      final maxExtent = _tabsScroll.position.maxScrollExtent;
      const double estimatedTabWidth = 140.0;
      const double leftPadding = 12.0;
      final target = (index * estimatedTabWidth - leftPadding).clamp(
        0.0,
        maxExtent,
      );
      _tabsScroll.animateTo(
        target,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }

    doScroll();
  }

  Future<void> _scrollToSection(int index) async {
    if (index < 0) return;
    if (index >= _stickyEntryKeys.length) return;
    final targetKey = _stickyEntryKeys[index];
    final ctx = targetKey.currentContext;
    if (ctx == null) return;
    final box = ctx.findRenderObject();
    if (box is! RenderBox) return;
    final scrollBox = _scroll.position.context.notificationContext
        ?.findRenderObject() as RenderBox?;
    if (scrollBox == null) {
      await Scrollable.ensureVisible(
        ctx,
        duration: const Duration(milliseconds: 700),
        curve: Curves.easeInOutCubic,
      );
      return;
    }
    final delta = box.localToGlobal(Offset.zero, ancestor: scrollBox).dy -
        _kStickyBarHeight;
    final target = (_scroll.offset + delta).clamp(
      0.0,
      _scroll.position.maxScrollExtent,
    );
    await _scroll.animateTo(
      target,
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeInOutCubic,
    );
  }

  Future<void> _scrollToTop() async {
    if (!_scroll.hasClients) return;
    unawaited(HapticFeedback.lightImpact());
    // Remonter doit toujours révéler le footer (jamais « collé » masqué).
    updateFooterVisibility(ref, true);
    await _scroll.animateTo(
      0,
      duration: const Duration(milliseconds: 900),
      curve: Curves.easeInOutCubic,
    );
  }

  /// Pull-to-refresh handler. Wraps the provider's refresh + clears pending
  /// feedback (the new state replaces yesterday's session) + scrolls to top.
  Future<void> _handleRefresh() async {
    if (_pendingFeedback.isNotEmpty) {
      setState(_pendingFeedback.clear);
    }
    final outcome = await ref.read(fluxContinuProvider.notifier).refresh();
    final now = DateTime.now();
    // Un refresh explicite réarme le cooldown foreground : pas de double refetch
    // si l'app repasse en arrière-plan puis revient juste après.
    _lastForegroundRefreshAt = now;
    if (!mounted) return;
    // Escalade « rien de neuf » → Flâner (décidée avec le PO). Décision pure
    // déléguée à [essentielEmptyPullAction] (testable sans monter l'écran).
    final action = essentielEmptyPullAction(
      succeeded: outcome.succeeded,
      newSinceMorning: outcome.newSinceMorning,
      lastEmptyPullAt: _lastEmptyPullAt,
      now: now,
    );
    switch (action) {
      case EssentielEmptyPullAction.redirect:
        // Re-pull à vide rapproché → bascule auto vers Flâner (contenu frais).
        // Return early : pas de scroll-to-top, on change d'onglet.
        _lastEmptyPullAt = null;
        context.go(RoutePaths.flaner);
        return;
      case EssentielEmptyPullAction.hint:
        // 1er pull à vide → SnackBar + CTA « Flâner » (aucune redirection).
        _lastEmptyPullAt = now;
        _showRienDeNeufFlanerSnackBar();
      case EssentielEmptyPullAction.none:
        // Nouveauté ou refresh borné/échoué → reset de l'escalade.
        _lastEmptyPullAt = null;
    }
    if (_scroll.hasClients) {
      unawaited(
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        ),
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState appState) {
    if (appState == AppLifecycleState.paused) {
      _backgroundedAt = DateTime.now();
      // Suspend le chrono de session : le temps en arrière-plan ne compte pas.
      _sessionTracker.pause(DateTime.now());
      // Story 33.1 — vide la file des décisions de tri avant que l'OS ne puisse
      // tuer le process. Sans ce flush, un tri interrompu perdrait tout ce qui
      // n'a pas atteint le debounce de 2 s.
      unawaited(ref.read(essentielTriageProvider.notifier).flush());
    } else if (appState == AppLifecycleState.resumed) {
      // Relance le chrono foreground puis tente la ré-actualisation.
      _sessionTracker.resume(DateTime.now());
      _maybeRefreshEssentielOnForeground();
    }
  }

  /// Émet la session digest (garde-fou doomscroll, story 9.8) — durée foreground
  /// cumulée + complétion de la carte de clôture. Fire-once (délégué au
  /// [DigestSessionTracker]). Best-effort : n'impacte jamais le teardown.
  void _emitDigestSession() {
    final payload = _sessionTracker.finish(DateTime.now());
    if (payload == null) return;
    // Les compteurs par-article ne sont pas instrumentés ici (hors périmètre du
    // garde-fou) : seuls comptent la durée et la complétion de clôture.
    unawaited(
      _analytics.trackDigestSession(
            digestDate: DateTime.now().toIso8601String().split('T').first,
            articlesRead: 0,
            articlesSaved: 0,
            articlesDismissed: 0,
            articlesPassed: 0,
            totalTimeSeconds: payload.totalTimeSeconds,
            closureAchieved: payload.closureAchieved,
            streak: _lastKnownStreak,
          ),
    );
  }

  /// Story 9.8 — au retour au premier plan, L'Essentiel se ré-actualise « comme
  /// un feed vivant », mais **sans jamais casser la lecture en cours**. On ne
  /// rafraîchit que si :
  /// - l'utilisateur regarde effectivement le feed Essentiel (route exacte
  ///   `/flux-continu` — pas un article ouvert, pas l'onglet Flâner) ;
  /// - il est **en haut** de ce feed (sticky bar pas encore révélée) ;
  /// - le passage en arrière-plan a duré assez longtemps et le cooldown est
  ///   écoulé ([shouldRefreshEssentielOnForeground]).
  ///
  /// Le refresh passe par [FluxContinuNotifier.refresh] (sans `AsyncLoading` →
  /// pas de squelette) ; l'utilisateur étant en haut, le hero (index 0) reste en
  /// place : la ré-actualisation est invisible, zéro saut de scroll.
  void _maybeRefreshEssentielOnForeground() {
    if (!mounted) return;
    final backgroundedAt = _backgroundedAt;
    _backgroundedAt = null;
    final now = DateTime.now();
    final backgroundedFor =
        backgroundedAt == null ? null : now.difference(backgroundedAt);
    final sinceLastRefresh = _lastForegroundRefreshAt == null
        ? null
        : now.difference(_lastForegroundRefreshAt!);
    final onEssentielRoot =
        GoRouter.of(context).routerDelegate.currentConfiguration.uri.path ==
            RoutePaths.fluxContinu;
    // « En haut » = feed Essentiel visible, son scroll attaché, au ras du sommet
    // (sous le seuil sticky). En mode édition passée, le CustomScrollView live
    // n'est pas monté → `_scroll` sans clients → traité « pas en haut » → aucun
    // refresh (on ne touche pas au live pendant qu'une édition passée est ouverte).
    final atTop = onEssentielRoot &&
        _scroll.hasClients &&
        _scroll.offset <= _kStickyThreshold;
    if (!shouldRefreshEssentielOnForeground(
      atTop: atTop,
      backgroundedFor: backgroundedFor,
      sinceLastRefresh: sinceLastRefresh,
    )) {
      return;
    }
    _lastForegroundRefreshAt = now;
    // Refresh auto au retour premier plan : à vide → SnackBar « Flâner »
    // uniquement (jamais de redirection auto — réservée au re-pull explicite),
    // et **sans** toucher le compteur d'escalade. Déjà cooldown-gaté par
    // [shouldRefreshEssentielOnForeground], donc pas de spam.
    unawaited(
      ref.read(fluxContinuProvider.notifier).refresh().then((outcome) {
        if (!mounted) return;
        if (outcome.succeeded && outcome.newSinceMorning == 0) {
          _showRienDeNeufFlanerSnackBar();
        }
      }),
    );
  }

  /// SnackBar « rien de neuf » + CTA « Flâner » de L'Essentiel. Les deux chemins
  /// de refresh (pull explicite et retour premier plan) l'affichent à l'identique
  /// ; l'appelant garantit `mounted` au préalable.
  void _showRienDeNeufFlanerSnackBar() {
    NotificationService.showInfo(
      'Rien de neuf dans ton Essentiel pour l\'instant.',
      actionLabel: 'Flâner',
      icon: PhosphorIcons.compass(),
      onAction: () => context.go(RoutePaths.flaner),
      context: context,
    );
  }

  /// Opens the dedicated full-page view for a [FeedThemeSection]. The
  /// section's current snapshot is passed via `extra` so the page renders
  /// the cached items immediately rather than waiting on the provider.
  void _openThemeSection(BuildContext context, FeedThemeSection section) {
    final key = Uri.encodeComponent(sectionKey(section));
    ref.read(tourneeLastDedicatedSectionProvider.notifier).state = sectionKey(
      section,
    );
    context
        .push('${RoutePaths.fluxContinu}/theme/$key', extra: section)
        .then((_) => _restoreLastDedicatedSection());
  }

  /// PR « Sources dans la Tournée » — ouvre la vue détail d'une section source
  /// (curation complète de la source). Miroir de [_openThemeSection], route
  /// `/flux-continu/source/:id` (id = sectionKey = `source:<uuid>`).
  void _openSourceSection(BuildContext context, FeedThemeSection section) {
    final key = Uri.encodeComponent(sectionKey(section));
    ref.read(tourneeLastDedicatedSectionProvider.notifier).state = sectionKey(
      section,
    );
    context
        .push('${RoutePaths.fluxContinu}/source/$key', extra: section)
        .then((_) => _restoreLastDedicatedSection());
  }

  /// Story 22.3 — ouvre la sheet « Pourquoi cette section ? » d'une suggestion
  /// « Choisie pour vous ». Les actions garder/retirer délèguent au notifier
  /// (promotion en favori / dismiss local), avec confirmation discrète.
  void _openSuggestionSheet(
    BuildContext context,
    FeedThemeSection section,
    FluxContinuNotifier notifier,
  ) {
    showSuggestionReasonSheet(
      context,
      sectionTitle: section.label,
      reason: section.reason,
      onKeep: () async {
        // N'annonce le succès que si la promotion a réellement persisté en DB.
        // Un faux « Ajoutée » sur échec réseau laissait une divergence local/DB
        // que le cold boot rejouait en éviction.
        try {
          await notifier.promoteSuggestion(section);
          NotificationService.showSuccess('Ajoutée à tes favoris');
        } catch (_) {
          NotificationService.showError(
            'Impossible d\'ajouter à tes favoris pour le moment.',
          );
        }
      },
      onDismiss: () async {
        await notifier.dismissSuggestion(section);
        NotificationService.showSuccess('Suggestion retirée');
      },
    );
  }

  /// Opens the dedicated full-page view for a [DigestTopicSection]
  /// (Actus du jour, Bonnes Nouvelles). Mirrors [_openThemeSection].
  void _openDigestSection(BuildContext context, DigestTopicSection section) {
    ref.read(tourneeLastDedicatedSectionProvider.notifier).state = sectionKey(
      section,
    );
    context
        .push(
          '${RoutePaths.fluxContinu}/section/${sectionKey(section)}',
          extra: section,
        )
        .then((_) => _restoreLastDedicatedSection());
  }

  void _restoreLastDedicatedSection() {
    if (!mounted) return;
    final key = ref.read(tourneeLastDedicatedSectionProvider);
    final sections = ref.read(fluxContinuProvider).valueOrNull?.sections;
    if (key == null || sections == null) return;
    final sectionIndex = sections.indexWhere((s) => sectionKey(s) == key);
    if (sectionIndex < 0 || sectionIndex >= _sectionKeys.length) return;
    final stickyIndex = _stickyEntryKeys.indexOf(_sectionKeys[sectionIndex]);
    if (stickyIndex >= 0) {
      unawaited(_scrollToSection(stickyIndex));
    }
  }

  /// Deep-link « file droit vers une section » du rituel matinal : planifie la
  /// consommation de [pendingFeedSectionKeyProvider] pour le prochain post-frame
  /// (une seule fois tant qu'elle n'a pas abouti). Le retry borné absorbe le
  /// délai de mesure des sections (`_stickyEntryKeys` peuplé après layout).
  void _scheduleConsumePendingSection() {
    if (_pendingSectionConsumeScheduled) return;
    _pendingSectionConsumeScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _tryConsumePendingSection(0);
    });
  }

  /// Tente de résoudre + scroller vers la section en attente. Re-tente ~30×
  /// toutes les 40 ms tant que les sections ne sont pas mesurées (mécanique du
  /// `scrollToFocus` de la maquette), puis abandonne en remettant le provider à
  /// `null` (une clé introuvable / un layout absent ne doit jamais boucler).
  void _tryConsumePendingSection(int attempt) {
    if (!mounted) {
      _pendingSectionConsumeScheduled = false;
      return;
    }
    final key = ref.read(pendingFeedSectionKeyProvider);
    if (key == null) {
      _pendingSectionConsumeScheduled = false;
      return;
    }
    if (_resolveAndScrollToSectionKey(key) || attempt >= 30) {
      ref.read(pendingFeedSectionKeyProvider.notifier).state = null;
      _pendingSectionConsumeScheduled = false;
      return;
    }
    Future.delayed(
      const Duration(milliseconds: 40),
      () => _tryConsumePendingSection(attempt + 1),
    );
  }

  /// Résout une `sectionKey` vers son entrée sticky et y scrolle. Retourne
  /// `false` (retry) tant que la section n'est pas montée/mesurée. Mécanique
  /// identique à [_restoreLastDedicatedSection], mais gardée sur la présence
  /// effective du `currentContext` (sinon `_scrollToSection` no-op silencieux).
  bool _resolveAndScrollToSectionKey(String key) {
    final sections = ref.read(fluxContinuProvider).valueOrNull?.sections;
    if (sections == null) return false;
    final sectionIndex = sections.indexWhere((s) => sectionKey(s) == key);
    if (sectionIndex < 0 || sectionIndex >= _sectionKeys.length) return false;
    final stickyIndex = _stickyEntryKeys.indexOf(_sectionKeys[sectionIndex]);
    if (stickyIndex < 0) return false;
    if (_stickyEntryKeys[stickyIndex].currentContext == null) return false;
    unawaited(_scrollToSection(stickyIndex));
    return true;
  }

  /// Opens an article. ReadSyncService propagates the read state after the
  /// one-second threshold; returning sooner must leave the card unread.
  Future<void> _openArticle(BuildContext context, Object article) async {
    if (article is DigestItem) {
      await context.push(
        '${RoutePaths.fluxContinu}/content/${article.contentId}',
        extra: article.toPreviewContent(),
      );
    } else if (article is Content) {
      await context.push(
        '${RoutePaths.fluxContinu}/content/${article.id}',
        extra: article,
      );
    } else if (article is EssentielArticle) {
      await context.push(
        '${RoutePaths.fluxContinu}/content/${article.contentId}',
        extra: article.toPreviewContent(),
      );
    } else {
      return;
    }
  }

  // ---------------------------------------------------------------------------
  // Inline-feedback flow (swipe-left)
  // ---------------------------------------------------------------------------

  void _onSwipeDismiss(String contentId) {
    if (contentId.isEmpty) return;
    final notifier = ref.read(fluxContinuProvider.notifier);
    unawaited(notifier.markHiddenRemote(contentId));
    setState(() => _pendingFeedback.add(contentId));
  }

  void _scheduleGestureNudge() {
    if (_gestureNudgeRequested) return;
    _gestureNudgeRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final location = GoRouter.of(
        context,
      ).routerDelegate.currentConfiguration.uri.path;
      if (!location.startsWith(RoutePaths.fluxContinu)) {
        _gestureNudgeRequested = false;
        return;
      }
      final coordinator = ref.read(nudgeCoordinatorProvider);
      if (coordinator.activeId != null) return;
      final swipe = await coordinator.request(NudgeIds.feedSwipeHint);
      if (!mounted) return;
      if (swipe == NudgeIds.feedSwipeHint) {
        setState(() => _showSwipeHint = true);
      }
      // L'ancien tooltip « aperçu au long-press » (NudgeIds.feedPreviewLongpress)
      // n'est plus déclenché ici : sur Essentiel/Flux il est remplacé par le
      // nudge auto-grow (cf. _maybeTriggerAutoGrow). Flâner garde son tooltip.
    });
  }

  void _onSwipeHintComplete() {
    if (mounted) setState(() => _showSwipeHint = false);
    final coordinator = ref.read(nudgeCoordinatorProvider);
    if (coordinator.activeId == NudgeIds.feedSwipeHint) {
      unawaited(coordinator.dismiss(markSeen: false));
    }
  }

  void _recordSwipeConversion() {
    if (_showSwipeHint && mounted) {
      setState(() => _showSwipeHint = false);
    }
    unawaited(
      ref
          .read(nudgeCoordinatorProvider)
          .recordConversion(NudgeIds.feedSwipeHint),
    );
  }

  void _recordLongPressConversion() {
    // Un vrai long-press = l'aperçu est découvert → coupe le nudge auto-grow
    // définitivement pour cet utilisateur.
    unawaited(ref.read(autoGrowNudgeSchedulerProvider).markDiscovered());
  }

  void _resolveFeedback(String contentId) {
    if (!mounted) return;
    if (!_pendingFeedback.contains(contentId)) return;
    setState(() => _pendingFeedback.remove(contentId));
    ref.read(fluxContinuProvider.notifier).confirmDismiss(contentId);
  }

  void _undoFeedback(String contentId) {
    if (!mounted) return;
    unawaited(ref.read(fluxContinuProvider.notifier).undoHide(contentId));
    setState(() => _pendingFeedback.remove(contentId));
  }

  void _trackFeedbackSubmit(String contentId, String feedbackType) {
    unawaited(
      ref.read(analyticsServiceProvider).trackArticleFeedbackSubmitted(
            contentId: contentId,
            feedbackType: feedbackType,
            origin: 'flux_continu',
          ),
    );
  }

  Future<void> _onSelectFeedbackChip(
    BuildContext context,
    String contentId,
    FluxFeedbackChip chip,
  ) async {
    final state = ref.read(fluxContinuProvider).valueOrNull;
    final article = state == null ? null : _lookupArticle(state, contentId);
    switch (chip) {
      case FluxFeedbackChip.source:
        _trackFeedbackSubmit(contentId, 'less_source');
        if (article != null && context.mounted) {
          await TopicChip.showArticleSheet(
            context,
            articleToContent(article),
            initialSection: ArticleSheetSection.source,
            highlightInitialSection: true,
          );
        }
        _resolveFeedback(contentId);
      case FluxFeedbackChip.topic:
        _trackFeedbackSubmit(contentId, 'less_topic');
        if (article != null && context.mounted) {
          await TopicChip.showArticleSheet(
            context,
            articleToContent(article),
            initialSection: ArticleSheetSection.topic,
            highlightInitialSection: true,
          );
        }
        _resolveFeedback(contentId);
      case FluxFeedbackChip.alreadySeen:
        _trackFeedbackSubmit(contentId, 'already_seen');
        _resolveFeedback(contentId);
    }
  }

  /// Finds an article in the current state by its content id.
  Object? _lookupArticle(FluxContinuState state, String contentId) {
    for (final s in state.sections) {
      switch (s) {
        case EssentielSection(:final articles):
          for (final a in articles) {
            if (a.contentId == contentId) return a;
          }
        case AlertsSection():
          // Le rappel d'alertes ne porte que des sources, jamais d'article.
          break;
        case CarouselSection(:final data):
          for (final c in data.items) {
            if (c.id == contentId) return c;
          }
        case DigestTopicSection(:final topics):
          for (final t in topics) {
            final lead = pickTopicLead(t);
            if (lead.contentId == contentId) return lead;
          }
        case FeedThemeSection(:final items):
          for (final c in items) {
            if (c.id == contentId) return c;
          }
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Flow post-onboarding (présenté sur Essentiel chargé, cf.
  // postOnboardingFlowPendingProvider)
  // ---------------------------------------------------------------------------

  /// Planifie le flow post-onboarding pour le prochain post-frame, une seule
  /// fois par montage. Le garde-fou est armé immédiatement pour qu'aucun
  /// rebuild concurrent n'empile de second callback.
  void _schedulePostOnboardingFlow() {
    if (_postOnboardingFlowRan) return;
    _postOnboardingFlowRan = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_runPostOnboardingFlow());
    });
  }

  /// Joue, dans l'ordre, sur le `context`/`ref` stables d'Essentiel chargé :
  /// 1. le dialog des sujets personnalisés échoués (si non vide),
  /// 2. la modal de choix de thème,
  /// 3. la modal d'activation des notifications.
  /// La page Essentiel chargée sert de fond aux modales : à leur fermeture elle
  /// est révélée intacte (plus d'écran gris ni de contexte démonté).
  /// Façade post-onboarding : consomme le flag (anti-replay), puis joue le tour
  /// guidé **d'abord** ; à sa conclusion (`onComplete`, tiré une seule fois sur
  /// finish/skip — ou immédiatement si le tour a déjà été vu), enchaîne les
  /// modales (dialog customs échoués → thème → notif). `onComplete` est exécuté
  /// par le controller (état Riverpod stable) : on re-garde `mounted` à l'entrée
  /// de [_runPostOnboardingModals], jamais de `ref` après démontage.
  Future<void> _runPostOnboardingFlow() async {
    if (!mounted) return;
    final failedCustomTopics = ref.read(postOnboardingFlowPendingProvider);
    if (failedCustomTopics == null) return;
    // Consomme le flag immédiatement : un refetch/rebuild ne doit pas rejouer.
    ref.read(postOnboardingFlowPendingProvider.notifier).state = null;

    await ref.read(guidedTourControllerProvider.notifier).start(
          onComplete: () =>
              unawaited(_runPostOnboardingModals(failedCustomTopics)),
        );
  }

  /// Les modales historiques, jouées une fois le tour guidé conclu. Le `failed`
  /// est capturé dans la closure `onComplete` pour survivre à la durée du tour.
  Future<void> _runPostOnboardingModals(List<String> failedCustomTopics) async {
    if (!mounted) return;

    if (mounted && failedCustomTopics.isNotEmpty) {
      // Dialog bloquant : les bottom sheets suivants poseraient un barrier qui
      // masquerait une SnackBar. Le dialog garantit que l'utilisateur voit
      // l'info ("tu pourras les réajouter").
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          content: Text(
            OnboardingFallbackStrings.failedCustomTopicsMessage(
              failedCustomTopics,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    if (mounted) {
      await showThemeChoiceBottomSheet(context, ref);
    }

    // Modal de choix d'affichage (Normal / Minimaliste / Ludique), jouée une
    // seule fois en fin d'onboarding, entre le thème et la modal notif. Gardée
    // par un flag Hive persistant (belt-and-suspenders : ce flow ne tourne déjà
    // qu'une fois). Sheet dismissible (pas de barrier non-fermable) → non
    // intrusive, conforme à la directive PO « conservateur ».
    if (mounted) {
      final settingsBox = await Hive.openBox<dynamic>('settings');
      final displayModeModalSeen = settingsBox.get('display_mode_modal_seen',
          defaultValue: false) as bool;
      if (!displayModeModalSeen && mounted) {
        await showDisplayModeBottomSheet(context, ref);
        await settingsBox.put('display_mode_modal_seen', true);
      }
    }

    if (mounted) {
      await showNotificationActivationModal(
        context,
        ref,
        trigger: ActivationTrigger.onboarding,
      );
      // Marque la modal notif comme consommée pour la session : l'arbitre
      // first-impression ne la reproposera pas et laisse passer les nudges.
      if (mounted) {
        ref.read(notifModalConsumedThisSessionProvider.notifier).state = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(fluxContinuProvider);
    final data = state.valueOrNull;
    // Snapshot best-effort du streak courant pour l'event de session (garde-fou
    // doomscroll, story 9.8) : lu au fil des builds, consommé au dispose.
    _lastKnownStreak =
        ref.read(streakActivityProvider).valueOrNull?.currentStreak ??
            _lastKnownStreak;
    // EPIC « Lettre du jour » — sélection de date du bloc Essentiel. Hors
    // « Aujourd'hui », on rend une lettre passée autonome (lecture seule) et on
    // masque la tournée live + son sticky/snap (incohérent avec une édition
    // passée).
    final selection = ref.watch(selectedEditionDateProvider);
    final isPastEdition = selection is! EditionToday;
    // Squelette : fenêtre de loading initiale (avant 1ère peinture) OU état
    // squelette explicite émis par le provider (cache d'hier invalidé / cold
    // start). On rend alors un scaffold placeholder, jamais le spinner plein
    // écran ni le vrai `_buildContent`.
    final isSkeleton = !_firstPaintDone ||
        state is AsyncLoading ||
        (data?.isSkeleton ?? false);
    // Changer d'édition remet la lettre passée en haut (le feed live garde sa
    // position via son contrôleur dédié).
    ref.listen(selectedEditionDateProvider, (_, next) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        if (next is! EditionToday && _editionScroll.hasClients) {
          _editionScroll.jumpTo(0);
        }
      });
    });
    // EPIC « Lettre du jour » — quand une **édition passée** se charge avec
    // succès (data non stale/vide), on marque son jour « rattrapé » dans le set
    // local (frontend-only) pour que la timeline reflète l'action tout de suite,
    // sans attendre la prochaine synchro streaks. Restreint aux jours passés :
    // le statut « Cette semaine » se dérive des dayKeys (jamais de la clé
    // 'week'), la persister ne ferait que re-déclencher l'agrégation hebdo.
    ref.listen<AsyncValue<EditionEssentielState>>(editionEssentielProvider,
        (_, next) {
      final edition = next.valueOrNull;
      if (edition == null || edition.isStaleOrEmpty) return;
      final selection = edition.selection;
      if (selection is! EditionPastDay) return;
      ref.read(editionCaughtUpProvider.notifier).markCaughtUp(selection.key);
    });
    // Re-tap de l'onglet actif (depuis le shell) → remonter en haut.
    ref.listen(essentielScrollTriggerProvider, (_, __) => _scrollToTop());
    ref.listen(tourneeLastDedicatedSectionProvider, (_, __) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _restoreLastDedicatedSection();
      });
    });
    // Tour guidé (étape « descends dans tes cartes ») : le bridge pose la clé
    // de la section à révéler ; on l'`ensureVisible` puis on remet à null.
    ref.listen<GlobalKey?>(tourScrollTargetProvider, (_, key) {
      if (key == null) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = key.currentContext;
        if (ctx != null) {
          Scrollable.ensureVisible(
            ctx,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutCubic,
            alignment: 0.1,
          );
        }
        if (mounted) {
          ref.read(tourScrollTargetProvider.notifier).state = null;
        }
      });
    });
    // Flow post-onboarding : joué une seule fois quand Essentiel a chargé ses
    // **vraies** données (derrière les modales thème & notifications). On exclut
    // l'état squelette : le flow attend du contenu réel. Couvre la transition
    // loading→data (via le listen) et le cas où l'état est déjà `data` au
    // montage (check direct planifié en post-frame).
    ref.listen<AsyncValue<FluxContinuState>>(fluxContinuProvider, (_, next) {
      if (next is AsyncData<FluxContinuState> &&
          !next.value.isSkeleton &&
          ref.read(postOnboardingFlowPendingProvider) != null) {
        _schedulePostOnboardingFlow();
      }
    });
    if (!isSkeleton &&
        state is AsyncData<FluxContinuState> &&
        ref.read(postOnboardingFlowPendingProvider) != null) {
      _schedulePostOnboardingFlow();
    }
    // Source unique : aligne [_sectionKeys] + [_stickyEntryKeys] sur les slivers
    // et dérive les descripteurs d'onglets (label+accent), dans le même ordre.
    // Hors squelette uniquement : le scaffold placeholder n'attache pas les
    // GlobalKeys de section ni la physics de snap.
    // En mode édition passée, le sticky/snap de la tournée live est masqué : on
    // ne synchronise ni les onglets ni les ancres (le contenu rendu n'est pas
    // celui du provider live).
    final stickyTabs = (isSkeleton || isPastEdition)
        ? const <StickyTab>[]
        : _syncStickyEntries(data);
    if (!isSkeleton && !isPastEdition) {
      // Sections don't resize mid-session, so we refresh the snap anchors only
      // on these content/layout-driven rebuilds — never per scroll frame.
      _safeAreaBottom = MediaQuery.paddingOf(context).bottom;
      _scheduleAnchorRecompute();
    }
    // Deep-link « file droit vers une section » posé par le rituel matinal :
    // consommé une fois les sections live montées (jamais en squelette ni en
    // édition passée — la tournée live n'y est pas rendue). `ref.watch` rejoue
    // ce build quand la clé est remise à `null` (fin de consommation).
    final pendingSectionKey = ref.watch(pendingFeedSectionKeyProvider);
    if (pendingSectionKey != null && !isSkeleton && !isPastEdition) {
      _scheduleConsumePendingSection();
    }
    return Scaffold(
      backgroundColor: context.facteurColors.backgroundPrimary,
      // Header & footer vivent dans le scaffold de page partagé :
      // l'écran ne fournit plus de bottomNavigationBar ni de header, et son top
      // inset est déjà consommé par le header partagé.
      body: SafeArea(
        top: false,
        bottom: false,
        child: Stack(
          children: [
            if (isPastEdition)
              _buildPastEdition(context, selection)
            else if (isSkeleton)
              _FluxContinuSkeleton(sections: data?.sections ?? const [])
            else
              state.when(
                loading: () => const _FluxContinuSkeleton(sections: []),
                error: (e, _) => _ErrorView(
                  error: e,
                  onRetry: () =>
                      ref.read(fluxContinuProvider.notifier).refresh(),
                ),
                data: (data) => _buildContent(context, data),
              ),
            if (!isSkeleton && !isPastEdition)
              _StickyHostOverlay(
                stickyVisible: _stickyVisible,
                activeIndex: _activeIndex,
                tabs: stickyTabs,
                onTapTab: _scrollToSection,
                tabsController: _tabsScroll,
                onReorder: _onHeaderReorder,
                onDragStart: () => _headerDragging = true,
                onDragEnd: () => _headerDragging = false,
              ),
            // Pull-to-refresh discoverability pill.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: IgnorePointer(
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 280),
                    opacity: _showPullHint ? 1.0 : 0.0,
                    child: _PullToRefreshHint(active: _showPullHint),
                  ),
                ),
              ),
            ),
            // Hint one-shot de réorganisation, posé sous la barre sticky (en
            // overlay : ne consomme aucune hauteur de layout).
            if (!isSkeleton && !isPastEdition)
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: SafeArea(
                  bottom: false,
                  child: IgnorePointer(
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 280),
                      opacity: _showDragHint ? 1.0 : 0.0,
                      child: const _HeaderDragHint(),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Construit la liste ordonnée d'« entrées sticky » (sections + cartes
  /// virtuelles Mot du jour / Citation) reflétant l'ordre exact des slivers de
  /// [_buildContent]. Synchronise [_sectionKeys] (1 clé/section) et
  /// [_stickyEntryKeys] (clés combinées pour le suivi actif + le scroll), puis
  /// retourne les descripteurs d'onglets (label+accent) dans le même ordre.
  List<StickyTab> _syncStickyEntries(FluxContinuState? state) {
    if (state == null) {
      _stickyEntryKeys.clear();
      return const [];
    }
    if (_sectionKeys.length != state.sections.length) {
      _sectionKeys
        ..clear()
        ..addAll(List.generate(state.sections.length, (_) => GlobalKey()));
    }
    final citationPresent = state.quote != null && !state.closingDismissed;
    final grilleSlotIndex = state.grilleSlotIndex;
    // La carte perso est une entrée virtuelle (pas de section correspondante)
    // insérée juste après le hero lorsqu'elle est éligible mensuellement.
    final showPersonalisationCta =
        ref.watch(personalisationCtaShouldShowProvider).valueOrNull ?? false;
    final heroPresent =
        state.sections.isNotEmpty && state.sections.first is EssentielSection;

    final keys = <GlobalKey>[];
    final tabs = <StickyTab>[];
    void add(GlobalKey key, StickyTab tab) {
      keys.add(key);
      tabs.add(tab);
    }

    for (var i = 0; i < state.sections.length; i++) {
      if (grilleSlotIndex == i) {
        add(_grilleKey, _motDuJourTab);
      }
      final section = state.sections[i];
      final key = sectionKey(section);
      add(
        _sectionKeys[i],
        StickyTab(
          label: section.label,
          accent: section.accent,
          // Seules les vraies sections de la Tournée sont déplaçables ; le
          // héros Essentiel, les alertes et les sujets Flâner restent figés.
          orderKey: isTourneeReorderableKey(key) ? key : null,
        ),
      );
      // Destination de snap dédiée juste après le hero (entrée virtuelle,
      // sans section réelle — retourne -1 dans _sectionIndexForStickyIndex).
      if (showPersonalisationCta && heroPresent && i == 0) {
        add(_persoCardKey, _persoCardTab);
      }
    }
    if (grilleSlotIndex == state.sections.length) {
      add(_grilleKey, _motDuJourTab);
    }
    if (citationPresent) {
      add(_citationKey, _citationTab);
    }
    add(_closingKey, _closingTab);

    _stickyEntryKeys
      ..clear()
      ..addAll(keys);
    _stickyTabs = tabs;
    return tabs;
  }

  /// Réordre déclenché par le drag d'un onglet du header. Le remappage
  /// index → clé (et la contrainte des zones figées) vit dans
  /// [reorderTourneeTabKeys] ; la persistance est celle, partagée, de la sheet
  /// « Composer ma Tournée ».
  void _onHeaderReorder(int oldIndex, int newIndex) {
    final visibleKeys = reorderTourneeTabKeys(
      [for (final t in _stickyTabs) t.orderKey],
      oldIndex,
      newIndex,
    );
    if (visibleKeys == null) return;
    unawaited(persistTourneeEssentielReorder(ref, visibleKeys));
  }

  Widget _buildContent(BuildContext context, FluxContinuState state) {
    final notifier = ref.read(fluxContinuProvider.notifier);
    final colors = context.facteurColors;
    // Android peut fermer l'app programmatiquement ; iOS l'interdit (App
    // Store) → on y montre une phrase de clôture au lieu du bouton.
    final isAndroid = defaultTargetPlatform == TargetPlatform.android;

    // NB : [_sectionKeys] est synchronisé en amont par [_syncStickyEntries]
    // (appelé dans build) → on s'appuie sur cet alignement ici.

    return NotificationListener<ScrollNotification>(
      onNotification: _onScrollNotification,
      child: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: colors.primary,
        child: CustomScrollView(
          controller: _scroll,
          // Section-anchored snap woven into the fling's ballistic phase. The
          // platform parent (Bouncing/Clamping) is preserved via `applyTo`, so
          // overscroll/pull-to-refresh feel native; the snap only chooses the
          // resting position. AlwaysScrollable keeps the page scrollable even
          // when content is short.
          physics: AlwaysScrollableScrollPhysics(
            parent: _SectionSnapPhysics(
              anchors: _snapAnchors,
              onSnapCommit: _onSnapCommit,
            ),
          ),
          slivers: [
            // NB : le header (logo · streak · réglages) vit dans le scaffold de
            // page partagé — fixe, hors du scroll.
            const SliverToBoxAdapter(child: LettresNotificationBanner()),
            // EPIC « Lettre du jour » — plus de strip permanent : la navigation
            // temporelle vit désormais dans le déclencheur « rewind » de l'en-tête
            // de la carte Essentiel (EditionRewindTrigger → EditionTimelineSheet).
            // « Notif du jour » : file unique agrégeant les anciens nudges
            // inline (renudge / well-informed / géoloc) + messages profil.
            // Se gate elle-même sur les modales restantes et le bandeau
            // Lettres.
            const SliverToBoxAdapter(child: NotifDuJourCard()),
            // One SliverToBoxAdapter per section. Sections never resize during
            // a session, so the simpler non-lazy adapter is sufficient and
            // keeps the GlobalKey measurement reliable.
            //
            // The "Mes intérêts" intro (V10) is injected once, right before the
            // first user-favorite theme section. The computed index handles
            // both ordering modes (normal / sereine) by tracking the actual
            // position of the first favorite kind.
            ..._buildSectionSlivers(
              context: context,
              state: state,
              notifier: notifier,
            ),
            if (state.sections.isEmpty && state.grilleSlotIndex == null)
              SliverToBoxAdapter(
                child: _EmptySectionsHint(onRetry: notifier.refresh),
              ),
            // Citation du jour — clôture éditoriale en fin de tournée. Affichée
            // dès qu'une citation existe et que la tournée n'est pas clôturée
            // (`closingDismissed`) : replier la tournée ne doit pas la masquer,
            // c'est un rituel de fin de tournée.
            if (state.quote != null && !state.closingDismissed)
              SliverToBoxAdapter(
                child: KeyedSubtree(
                  key: _citationKey,
                  child: CitationDuJourCard(quote: state.quote!),
                ),
              ),
            // Carte « Fin de tournée » — toujours affichée (jamais masquée) : elle
            // reste le repère de clôture même après être passé sur Flâner.
            // « Continuer » navigue vers Flâner sans masquer la carte. « Refermer »
            // ferme réellement l'app sur Android (SystemNavigator.pop) ; sur iOS,
            // la fermeture programmatique est interdite → on masque le bouton et
            // on affiche une phrase de clôture à la place.
            // La carte feedback (Epic 13) est fusionnée SOUS `_closingKey` avec
            // la carte « Fin de tournée » : c'est la boîte portée par cette clé
            // que [_recomputeSnapAnchors] mesure pour cadrer le bas de la
            // section de clôture. Rendue en sliver séparé sans clé, elle était
            // invisible du calcul d'ancres → le snap la « repoussait » hors zone
            // de repos. La Column les réunit en une seule section mesurable.
            SliverToBoxAdapter(
              child: KeyedSubtree(
                key: _closingKey,
                // « Ton avis compte » est désormais une sous-carte interne de
                // « Tu es à jour », séparée par un divider : une seule boîte
                // visuelle mesurée par les ancres de snap. Sa hauteur change en
                // asynchrone (micro-vote → « Merci » ; l'invitation, elle, vit
                // désormais plus haut dans la tournée) ⇒ elle signale ces
                // relayouts pour rafraîchir les ancres de snap.
                // Enveloppée d'un VisibilityDetector (garde-fou doomscroll,
                // story 9.8) : la clôture est « atteinte » dès qu'elle est
                // visible à ≥ 50 %, fire-once (`_closingCardSeen`).
                child: VisibilityDetector(
                  key: const ValueKey('closing_card_vis'),
                  onVisibilityChanged: (info) {
                    if (info.visibleFraction >= 0.5) {
                      _sessionTracker.markClosureSeen();
                    }
                  },
                  child: ClosingCardV18(
                    onContinue: () => context.go(RoutePaths.flaner),
                    onClose: isAndroid ? () => SystemNavigator.pop() : null,
                    closeHint: isAndroid
                        ? null
                        : 'Vous pouvez refermer l’app — à demain',
                    secondary: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Constat rétrospectif des lectures abouties — après
                        // la lecture, jamais avant. Ne se rend pas du tout à
                        // zéro lecture aboutie (le cas majoritaire).
                        const DailyCompletionRecap(),
                        FeedbackClosingCard(
                          embedded: true,
                          onLayoutChanged: _scheduleAnchorRecompute,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            const SliverToBoxAdapter(child: SizedBox(height: 92)),
          ],
        ),
      ),
    );
  }

  static bool _isFavoriteSection(FluxSection s) => s is FeedThemeSection;

  List<SliverToBoxAdapter> _buildSectionSlivers({
    required BuildContext context,
    required FluxContinuState state,
    required FluxContinuNotifier notifier,
  }) {
    final favoriteCount = state.sections.where(_isFavoriteSection).length;
    final firstSwipeableSectionIndex = state.sections.indexWhere(
      (section) => switch (section) {
        EssentielSection() => false,
        AlertsSection() => false,
        CarouselSection() => false,
        DigestTopicSection(:final topics) => topics.any(
            (topic) =>
                !_pendingFeedback.contains(pickTopicLead(topic).contentId),
          ),
        FeedThemeSection(:final items) => items.any(
            (content) => !_pendingFeedback.contains(content.id),
          ),
      },
    );
    if (firstSwipeableSectionIndex >= 0) {
      _scheduleGestureNudge();
    }

    // La grande carte mensuelle et l'inline « Gérer / Tes N favoris »
    // s'excluent pour éviter deux appels à l'action concurrents.
    final customized = ref.watch(
      tourneeOrderPrefsProvider.select((s) => s.customized),
    );
    final showPersonalisationCta =
        ref.watch(personalisationCtaShouldShowProvider).valueOrNull ?? false;
    final heroPresent =
        state.sections.isNotEmpty && state.sections.first is EssentielSection;
    // Cible de l'inline (mode personnalisé) : la 1ʳᵉ section de contenu après le
    // hero. On l'embarque DANS le `KeyedSubtree` de cette section pour que son
    // ancre de snap inclue l'inline — il n'est plus orphelin « entre deux
    // snaps ». -1 = pas de cible (aucune section après le hero).
    final inlineTargetIndex = heroPresent
        ? (state.sections.length > 1 ? 1 : -1)
        : (state.sections.isNotEmpty ? 0 : -1);
    // Story 13.3 — l'invitation « un café en visio » s'ancre **2 sections avant
    // la dernière**, pas dans la carte de clôture : au tout dernier pixel de la
    // page, personne ne la voyait. Jamais sur le hero Essentiel (index 0), et
    // embarquée dans le `KeyedSubtree` de sa section pour les mêmes raisons de
    // snap que l'inline ci-dessus.
    // Story 32.1 — la carte carrousel de fin (hors-cap, non déplaçable) ne doit
    // pas décaler l'ancre : on l'exclut du décompte pour garder l'invitation ~2
    // sections de CONTENU avant la fin, comme avant l'ajout du carrousel.
    final anchorSectionCount =
        state.sections.isNotEmpty && state.sections.last is CarouselSection
        ? state.sections.length - 1
        : state.sections.length;
    final inviteTargetIndex = anchorSectionCount < 2
        ? -1
        : math.max(1, anchorSectionCount - 3);

    // Un seul indicateur d'attente pour toute la Tournée : la **première**
    // coquille de section encore non résolue porte le libellé « Ta tournée se
    // prépare… » (les autres restent des cartes shimmer nues).
    final firstPreparingIndex = state.sections.indexWhere(
      (s) => s is FeedThemeSection && s.isPlaceholder,
    );

    final slivers = <SliverToBoxAdapter>[];
    for (var i = 0; i < state.sections.length; i++) {
      if (state.grilleSlotIndex == i) {
        slivers.add(_grilleSliver(followedByNormalSection: true));
      }
      final section = state.sections[i];
      final isFavorite = _isFavoriteSection(section);
      // Story 22.3 — une section suggérée ne porte pas l'étoile « favori »
      // (elle se gère via son badge « Choisie pour vous » + sheet), pour ne pas
      // confondre les deux affordances.
      final isSuggested = section is FeedThemeSection && section.isSuggested;
      // Story 22.6 — impression au premier build d'une section suggérée
      // affichée (dédup persistée 1×/section/jour côté AnalyticsService ;
      // garde-fou mémoire pour ne pas relire SharedPreferences à chaque frame).
      if (isSuggested) {
        final key = sectionKey(section);
        if (_impressedSuggestionKeys.add(key)) {
          unawaited(
            ref.read(analyticsServiceProvider).trackSuggestionImpression(
                  sectionKey: key,
                  kind: section.kind.name,
                  dayKey: TourneeProgressService.dayKey(DateTime.now()),
                ),
          );
        }
      }
      // Mode personnalisé : préfixe l'inline « Gérer / Tes N favoris » au-dessus
      // du `SectionBlock`, à l'intérieur du subtree mesuré → l'inline fait
      // partie du bloc de snap de cette section (cf. [inlineTargetIndex]).
      final showInlineHere =
          customized && !showPersonalisationCta && i == inlineTargetIndex;
      slivers.add(
        SliverToBoxAdapter(
          child: KeyedSubtree(
            key: _sectionKeys[i],
            // Ancre du tour guidé (étape 2 — 1ʳᵉ section de contenu après le
            // hero). `inlineTargetIndex` désigne déjà cette section.
            child: KeyedSubtree(
              key: i == inlineTargetIndex ? tourActusSectionKey : null,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (showInlineHere)
                    MyInterestsIntro(
                      favoriteCount: favoriteCount,
                      onTapManage: () => showTourneeComposerSheet(context),
                    ),
                  _FreeReadEdgeFade(
                    index: i,
                    tallSections: _tallSections,
                    child: SectionBlock(
                      section: section,
                      showPreparingLabel: i == firstPreparingIndex,
                      onTapArticle: (a) => _openArticle(context, a),
                      onDismissArticle: _onSwipeDismiss,
                      pendingFeedbackIds: _pendingFeedback,
                      onSelectFeedbackChip: (id, chip) =>
                          _onSelectFeedbackChip(context, id, chip),
                      onResolveFeedback: _resolveFeedback,
                      onUndoFeedback: _undoFeedback,
                      enableSwipeHintOnFirstCard:
                          i == firstSwipeableSectionIndex && _showSwipeHint,
                      onSwipeHintComplete: _onSwipeHintComplete,
                      firstSwipeableCardAnchor: i == firstSwipeableSectionIndex
                          ? fluxContinuFirstCardKey
                          : null,
                      onSwipeConversion: _recordSwipeConversion,
                      onLongPressConversion: _recordLongPressConversion,
                      onTapFavorite: isFavorite && !isSuggested
                          ? () => showTourneeComposerSheet(context)
                          : null,
                      // Story 22.3 — badge « Choisie pour vous » → sheet explicative.
                      onTapSuggestionInfo: isSuggested
                          ? () =>
                              _openSuggestionSheet(context, section, notifier)
                          : null,
                      // Story 22.6 — CTA direct « Ajouter à mon Essentiel » sur
                      // la carte suggérée (origin=card pour l'analytics).
                      onPromoteSuggestion: isSuggested
                          ? () => notifier.promoteSuggestion(
                                section,
                                origin: 'card',
                              )
                          : null,
                      // Story 23.4 — bouton réglages (tune) sur la section veille →
                      // ouvre la config en édition. Réutilisé par le CTA d'état vide.
                      onTapSettings: section.kind == SectionKind.veille
                          ? () => context.push(
                                '${RoutePaths.veilleConfig}?mode=edit',
                              )
                          : null,
                      // CTA « Plus de sources (X) » / footer « Étoffer X » d'une
                      // section thème → page **dédiée** du thème
                      // (`ThemeSourcesScreen` : catalogue backend complet du
                      // thème, ajout par source). Sujet custom (hors macro-thème,
                      // sans page dédiée) → page d'ajout générique.
                      onAddSources: section is FeedThemeSection &&
                              section.kind == SectionKind.theme
                          ? () {
                              if (isCatalogTheme(section.themeSlug)) {
                                // Même route que le ThemeExplorer (catalogue
                                // dédié du thème) : push par chemin + `extra` =
                                // libellé pour le titre.
                                context.push(
                                  '/settings/sources/theme/${section.themeSlug}',
                                  extra: section.label,
                                );
                              } else {
                                context.pushNamed(RouteNames.addSource);
                              }
                            }
                          : null,
                      onSeeAll: section is FeedThemeSection
                          ? (section.kind == SectionKind.source
                              ? () => _openSourceSection(context, section)
                              : () => _openThemeSection(context, section))
                          : section is DigestTopicSection
                              ? () => _openDigestSection(context, section)
                              : null,
                    ),
                  ),
                  // Se rend en `SizedBox.shrink()` si l'utilisateur n'est pas
                  // éligible (gating segmenté backend).
                  if (i == inviteTargetIndex) const CallInviteEntry(),
                ],
              ),
            ),
          ),
        ),
      );
      // Carte mensuelle dédiée juste après le hero (son propre bloc de snap).
      if (showPersonalisationCta && heroPresent && i == 0) {
        slivers.add(
          SliverToBoxAdapter(
            child: KeyedSubtree(
              key: _persoCardKey,
              child: const PersonalisationCtaCard(),
            ),
          ),
        );
      }
    }
    if (state.grilleSlotIndex == state.sections.length) {
      slivers.add(_grilleSliver(followedByNormalSection: false));
    }
    return slivers;
  }

  // ───────────────────────────────────────────────────────────────────────────
  // EPIC « Lettre du jour » — rendu d'une édition passée (lecture seule)
  // ───────────────────────────────────────────────────────────────────────────

  void _backToToday() {
    ref.read(selectedEditionDateProvider.notifier).state = const EditionToday();
  }

  /// Rendu autonome d'une lettre passée / rétro « Cette semaine » : le bloc
  /// Essentiel est rendu en lecture seule (le déclencheur « rewind » vit dans son
  /// en-tête), et la tournée live est masquée (remplacée par une note +
  /// « Revenir à aujourd'hui »). Contrôleur + physique dédiés (pas de snap).
  Widget _buildPastEdition(BuildContext context, EditionSelection selection) {
    final colors = context.facteurColors;
    final asyncEdition = ref.watch(editionEssentielProvider);
    return RefreshIndicator(
      onRefresh: () async => ref.invalidate(editionEssentielProvider),
      color: colors.primary,
      child: CustomScrollView(
        controller: _editionScroll,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          ...asyncEdition.when(
            loading: () => const <Widget>[
              SliverToBoxAdapter(child: _HeroSkeleton()),
            ],
            error: (_, __) => <Widget>[_pastEmptySliver(context, selection)],
            data: (edition) => _pastDataSlivers(context, edition),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 92)),
        ],
      ),
    );
  }

  List<Widget> _pastDataSlivers(
    BuildContext context,
    EditionEssentielState edition,
  ) {
    if (edition.isStaleOrEmpty) {
      return <Widget>[_pastEmptySliver(context, edition.selection)];
    }
    // « Cette semaine » se rend via le **même** chemin single-day : sa valeur
    // « ce que tu as manqué » est portée par la sélection de contenu (héros =
    // non-lus de la semaine), pas par une UI dédiée.
    return _singleDaySlivers(context, edition);
  }

  /// Section de topics en lecture seule (pas d'`onDismissArticle`/feedback ⇒ pas
  /// de swipe). Réutilise `SectionBlock`. `blurb`/`illustrationAsset` reproduisent
  /// le `SectionBanner` de la lettre du jour (parité visuelle). `null` si la
  /// liste est vide (no-op).
  ///
  /// En vue hebdo, [previewCount] borne l'aperçu inline et câble « Tout lire »
  /// (bandeau + footer) vers la page section épinglée ([_openWeekSection]) dès
  /// qu'il y a plus de sujets que l'aperçu. Hors hebdo ([previewCount] `null`),
  /// tous les sujets se rendent inline sans « Tout lire ».
  Widget? _topicSectionSliver(
    BuildContext context, {
    required SectionKind kind,
    required String label,
    required Color accent,
    required List<DigestTopic> topics,
    int? previewCount,
    String? blurb,
    String? illustrationAsset,
  }) {
    if (topics.isEmpty) return null;
    final section = DigestTopicSection(
      kind: kind,
      label: label,
      accent: accent,
      coreVisibleCount: previewCount ?? topics.length,
      topics: topics,
      blurb: blurb,
      illustrationAsset: illustrationAsset,
    );
    // « Tout lire » seulement s'il reste des sujets au-delà de l'aperçu (sinon
    // la page section afficherait exactement le même contenu que l'inline).
    final onSeeAll = previewCount != null && topics.length > previewCount
        ? () => _openWeekSection(context, section)
        : null;
    return SliverToBoxAdapter(
      child: SectionBlock(
        section: section,
        onTapArticle: (a) => _openArticle(context, a),
        onSeeAll: onSeeAll,
      ),
    );
  }

  /// Ouvre la page section (`DigestSectionScreen`) **épinglée** sur l'agrégat
  /// hebdo (query `src=week`) : le contenu affiché est la [section] passée en
  /// `extra` (la semaine complète), pas le feed du jour. Utilisé par « Tout
  /// lire » de « Cette semaine ». Push simple (pas de restauration de scroll du
  /// feed du jour : la vue hebdo a son propre contrôleur, sans snap).
  void _openWeekSection(BuildContext context, DigestTopicSection section) {
    context.push(
      '${RoutePaths.fluxContinu}/section/${sectionKey(section)}?src=week',
      extra: section,
    );
  }

  /// Lettre **passée** (jour unique OU « Cette semaine ») rendue à parité visuelle
  /// avec la lettre du jour : héros → Actus → **Bonnes Nouvelles** → citation →
  /// carte de clôture (`ClosingCardV18.readOnly`). Mêmes widgets feuilles que le
  /// feed live (SectionBlock → EssentielHiFiCard / SectionBanner) ; chaque
  /// `SectionBlock` ne reçoit QUE `onTapArticle` ⇒ **lecture seule** (aucun
  /// swipe/feedback/favori). Sur ce chemin il n'y a ni snap ni feedforward
  /// (pas de listener sur `_editionScroll`) : les sections se suivent
  /// simplement. En vue hebdo : pas de citation, libellé « Actus de la
  /// semaine ». Les sections tournée personnalisées ne sont pas archivées par
  /// date ⇒ délibérément absentes (cf. docstring `editionEssentielProvider`).
  List<Widget> _singleDaySlivers(
    BuildContext context,
    EditionEssentielState edition,
  ) {
    final colors = context.facteurColors;

    // Corps de lettre : héros + Actus + Bonnes Nouvelles (chacun optionnel).
    // Les blurbs/illustrations reproduisent les bannières de la lettre du jour
    // (cf. flux_continu_provider `_kActusDuJourBlurb` / `_kBonnesBlurb`).
    final sections = <Widget>[];

    if (edition.heroArticles.isNotEmpty) {
      sections.add(
        SliverToBoxAdapter(
          child: SectionBlock(
            section: EssentielSection(articles: edition.heroArticles),
            onTapArticle: (a) => _openArticle(context, a),
          ),
        ),
      );
    }

    // En vue hebdo : agrégat **complet** (`topicsAll`/`bonnesAll`) + aperçu
    // borné (`kEditionWeekInlinePreview`) → « Tout lire » ouvre le reste. En
    // jour unique : liste du jour rendue intégralement inline (pas de préview).
    final actus = _topicSectionSliver(
      context,
      kind: SectionKind.essentiel,
      label: edition.isWeek ? 'Actus de la semaine' : 'Actus du jour',
      accent: colors.sectionEssentiel,
      topics: edition.isWeek ? edition.topicsAll : edition.topics,
      previewCount: edition.isWeek ? kEditionWeekInlinePreview : null,
      blurb: 'Les sujets les + couverts en France.',
      illustrationAsset: 'assets/notifications/facteur_avatar.png',
    );
    if (actus != null) sections.add(actus);

    final bonnes = _topicSectionSliver(
      context,
      kind: SectionKind.bonnes,
      label: 'Bonnes Nouvelles',
      accent: colors.sectionBonnes,
      topics: edition.isWeek ? edition.bonnesAll : edition.bonnesTopics,
      previewCount: edition.isWeek ? kEditionWeekInlinePreview : null,
      blurb: 'Un peu de douceur...',
      illustrationAsset: 'assets/notifications/facteur_goodnews.png',
    );
    if (bonnes != null) sections.add(bonnes);

    final slivers = <Widget>[...sections];

    if (edition.quote != null) {
      slivers.add(
        SliverToBoxAdapter(child: CitationDuJourCard(quote: edition.quote!)),
      );
    }

    // Même repère de fin de lettre que le jour, en lecture seule : l'action
    // primaire ramène à « Aujourd'hui » + note de contexte.
    slivers.add(
      SliverToBoxAdapter(
        child: ClosingCardV18.readOnly(
          onBackToToday: _backToToday,
          note: _pastEditionNote(edition.selection),
        ),
      ),
    );
    return slivers;
  }

  Widget _pastEmptySliver(BuildContext context, EditionSelection selection) {
    final message = switch (selection) {
      EditionWeek() => 'La semaine se prépare...',
      EditionPastDay(:final date) =>
        'Pas d\'édition pour ${formatFrenchLongDate(date)}.',
      EditionToday() => 'Pas d\'édition disponible.',
    };
    return SliverToBoxAdapter(
      child: _BackToTodayBlock(
        message: message,
        onBackToToday: _backToToday,
        onChooseAnotherDay: () => EditionTimelineSheet.show(context),
      ),
    );
  }

  String _pastEditionNote(EditionSelection selection) => switch (selection) {
        EditionWeek() =>
          'Tu consultes la rétro de la semaine. Tes recommandations du jour '
              'reviennent en sélectionnant « Aujourd’hui ».',
        EditionPastDay(:final date) =>
          'Tu lis la lettre du ${formatFrenchLongDate(date)}. Tes '
              'recommandations du jour reviennent en sélectionnant '
              '« Aujourd’hui ».',
        EditionToday() => 'Tes recommandations du jour reviennent en '
            'sélectionnant « Aujourd’hui ».',
      };
}

/// EPIC « Lettre du jour » — note discrète + bouton « Revenir à aujourd'hui »
/// affiché sous une lettre passée (footer) ou à la place du contenu quand aucune
/// édition n'est disponible (état vide).
class _BackToTodayBlock extends StatelessWidget {
  final String message;
  final VoidCallback onBackToToday;

  /// Action secondaire « Choisir un autre jour » (ouvre la timeline). Fournie
  /// dans l'état vide d'une lettre passée pour éviter le cul-de-sac « jour vide »
  /// sans forcer un passage par « Aujourd'hui ».
  final VoidCallback? onChooseAnotherDay;

  const _BackToTodayBlock({
    required this.message,
    required this.onBackToToday,
    this.onChooseAnotherDay,
  });

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.fromLTRB(
        FacteurSpacing.space4,
        FacteurSpacing.space2,
        FacteurSpacing.space4,
        FacteurSpacing.space4,
      ),
      padding: const EdgeInsets.all(FacteurSpacing.space4),
      decoration: facteurSurfaceCardDecoration(colors, shadow: false),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: colors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: FacteurSpacing.space3),
          Wrap(
            spacing: FacteurSpacing.space3,
            runSpacing: FacteurSpacing.space2,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonalIcon(
                onPressed: onBackToToday,
                icon: const Icon(Icons.today_rounded, size: 18),
                label: const Text('Revenir à aujourd’hui'),
              ),
              if (onChooseAnotherDay != null)
                TextButton.icon(
                  onPressed: onChooseAnotherDay,
                  icon: Icon(
                    PhosphorIcons.rewind(PhosphorIconsStyle.fill),
                    size: 16,
                  ),
                  label: const Text('Choisir un autre jour'),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Scaffold squelette du démarrage matinal : en-têtes de sections **réels**
/// (label/accent/illustration dérivés des prefs locales, portés par [sections])
/// + cartes placeholder, au lieu du `LoadingView` plein écran. Évite tout saut
/// de layout quand le contenu réel arrive : la structure est déjà en place, on
/// ne fait que remplir.
///
/// Volontairement **non scrollable** (NeverScrollableScrollPhysics) et sans la
/// physics de snap : le squelette est transitoire (≈ 1 round-trip), l'user est
/// en haut de page, et on ne touche pas au système snap/settle délicat. Reçoit
/// les coquilles de sections du provider ([FluxContinuState.sections] avec
/// `isSkeleton:true`) ; liste vide pendant la brève fenêtre de loading initiale
/// → on rend un hero + quelques placeholders génériques.
class _FluxContinuSkeleton extends StatelessWidget {
  final List<FluxSection> sections;

  const _FluxContinuSkeleton({required this.sections});

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[
      // Hero « L'Essentiel du jour » — placeholder pleine largeur en tête.
      const _HeroSkeleton(),
    ];
    if (sections.isEmpty) {
      // Fenêtre de loading initiale (pas encore de coquilles) → placeholders
      // génériques pour occuper l'espace sans labels.
      for (var i = 0; i < 3; i++) {
        children.add(
          const Padding(
            padding: EdgeInsets.only(top: 8),
            child: ExploreDiscoverySkeleton(),
          ),
        );
      }
    } else {
      var labelPlaced = false;
      for (final section in sections) {
        // Le hero est déjà rendu au-dessus.
        if (section is EssentielSection) continue;
        // Le rappel d'alertes n'a rien à pré-réserver : il n'existe que si des
        // cloches ont du neuf, ce que le squelette ne sait pas encore.
        if (section is AlertsSection) continue;
        // La carte carrousel est auto-portée (pas de banner/skeleton) et
        // n'apparaît qu'avec les vraies données de l'Essentiel — jamais en boot.
        if (section is CarouselSection) continue;
        final isSource =
            section is FeedThemeSection && section.kind == SectionKind.source;
        children.add(
          SectionBanner(
            title: section.label,
            accent: section.accent,
            blurb: section.blurb,
            illustrationAsset: isSource ? null : section.illustrationAsset,
            logoUrl: isSource ? section.sourceLogoUrl : null,
          ),
        );
        // Issue #1 — réserve la **hauteur finale** (coreVisibleCount cartes) avec
        // la même carte squelette que les coquilles de section, pour que la
        // séquence cold-skeleton → Phase 1 → Phase 2 garde une géométrie stable.
        // Libellé d'attente unique, porté par la 1ʳᵉ section rendue (parité avec
        // le placeholder de `SectionBlock`).
        children.addAll(sectionSkeletonCards(
          section.coreVisibleCount,
          firstCardLabel: labelPlaced ? null : kSectionPreparingLabel,
        ));
        labelPlaced = true;
        children.add(const SizedBox(height: 16));
      }
    }
    return ListView(
      // Le squelette ne défile pas — il est remplacé dès l'arrivée du contenu.
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 8, bottom: 92),
      children: children,
    );
  }
}

/// Exposé aux tests widget : `_HeroSkeleton` est privé mais sa géométrie
/// (hauteur réservée bien au-dessus de l'ancien bloc de 260 px, présence du
/// shimmer) est le garde-fou de ce fix. Monter `FluxContinuScreen` entier n'est
/// pas jouable en test (Supabase/Hive/GoRouter) — cf. `firstPreparingSectionIndex`.
@visibleForTesting
Widget essentielHeroSkeletonForTest() => const _HeroSkeleton();

/// Placeholder du hero « Ton Essentiel » pendant le squelette.
///
/// Reproduit la géométrie de la **carte de tri au swipe** (Story 33.1), qui est
/// le composant affiché par défaut : pastille date/météo, une **seule** carte à
/// trier, barre d'actions. Il réserve la **hauteur de pic** que la vraie carte
/// fige dès la 1ʳᵉ frame via [triageReservedHeight] — sinon le feed saute à
/// l'hydratation. Respire en shimmer (mêmes teintes que [SectionSkeletonCard])
/// pour se lire comme « l'Essentiel se prépare » et non comme une carte rognée.
class _HeroSkeleton extends StatelessWidget {
  const _HeroSkeleton();

  /// Slate nominal : la carte Essentiel est verrouillée à 5 articles. Sert
  /// uniquement à réserver la hauteur de pic du tri — aucun contenu n'est rendu.
  static const int _kNominalSlate = 5;

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    // Mêmes teintes que `SectionSkeletonCard` : le sweep est porté par le fond.
    final base = colors.textTertiary.withValues(alpha: 0.10);
    final highlight = colors.textTertiary.withValues(alpha: 0.04);

    // Hauteur de la pile de tri, identique à celle réservée par la vraie carte
    // (chrome=0 : la pastille/en-tête est rendue au-dessus de la pile).
    final stackHeight = triageReservedHeight(
      slateSize: _kNominalSlate,
      chromeHeight: 0,
      leadHeight: kHeroLeadHeight,
      mediumHeight: kHeroMediumHeight,
    );

    // Barre shimmer neutre réutilisée pour chaque coquille.
    Widget bar({double? width, required double height, double radius = 6}) =>
        Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: base,
            borderRadius: BorderRadius.circular(radius),
          ),
        );

    return Container(
      // Mêmes constantes que `EssentielHiFiCard` (theme.dart) → alignement
      // pixel-exact, aucun décalage horizontal à l'hydratation.
      margin: kEssentielCardMargin,
      decoration: facteurSurfaceCardDecoration(colors),
      child: Padding(
        padding: kEssentielCardPadding,
        child: Shimmer.fromColors(
          baseColor: base,
          highlightColor: highlight,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // En-tête : pastille date/météo (140) + filet accent + titre/chapô.
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  bar(width: 52, height: 140, radius: FacteurRadius.medium),
                  const SizedBox(width: FacteurSpacing.space2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(width: 28, height: 3, radius: 2),
                        const SizedBox(height: 10),
                        bar(width: 150, height: 18),
                        const SizedBox(height: 10),
                        bar(width: double.infinity, height: 11),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              // Pile de tri : progression + carte mono-article + barre d'actions.
              // La place restante (futurs « gardés ») reste vide, comme la carte
              // réelle dont la liste se construit vers le bas.
              SizedBox(
                height: stackHeight,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: kTriageProgressHeight,
                      child: Center(
                        child: bar(
                          width: double.infinity,
                          height: 6,
                          radius: 3,
                        ),
                      ),
                    ),
                    Container(
                      height: kTriageCardHeight,
                      decoration: BoxDecoration(
                        color: base,
                        borderRadius:
                            BorderRadius.circular(FacteurRadius.large),
                      ),
                    ),
                    SizedBox(
                      height: kTriageActionBarHeight,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            bar(width: 52, height: 52, radius: FacteurRadius.pill),
                            const SizedBox(width: FacteurSpacing.space6),
                            bar(width: 52, height: 52, radius: FacteurRadius.pill),
                            const SizedBox(width: FacteurSpacing.space6),
                            bar(width: 52, height: 52, radius: FacteurRadius.pill),
                          ],
                        ),
                      ),
                    ),
                    // Compteur « N sur M triés », qui ferme la liste des gardés
                    // — vide au boot, donc collé sous la barre d'actions.
                    SizedBox(
                      height: kTriageCounterHeight,
                      child: Align(
                        alignment: Alignment.bottomLeft,
                        child: bar(width: 110, height: 11),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Mutable, stable holder of the section framing offsets shared between the
/// screen state and the (immutable) [_SectionSnapPhysics]. The physics reads
/// [values] live each ballistic build; the state owns the writes.
class _SnapAnchors {
  List<SectionFrame> values = const [];
}

/// Scroll physics that folds a section-anchored snap into the fling's ballistic
/// phase. The platform parent (Bouncing iOS / Clamping Android) is preserved
/// via [applyTo], so `naturalLanding` inherits the native deceleration and the
/// snap is intrinsically un-gated by speed — it triggers on slow *and* fast
/// gestures.
class _SectionSnapPhysics extends ScrollPhysics {
  final _SnapAnchors anchors;

  /// Fired with the committed resting offset the instant a fling resolves a
  /// snap (finger lift), *before* the spring runs — lets the screen land the
  /// section haptic at the moment of passage instead of at settle. Preserved
  /// through [applyTo] so the platform-wrapped physics keeps calling it.
  final void Function(double committedTarget)? onSnapCommit;

  const _SectionSnapPhysics({
    required this.anchors,
    this.onSnapCommit,
    super.parent,
  });

  @override
  _SectionSnapPhysics applyTo(ScrollPhysics? ancestor) {
    return _SectionSnapPhysics(
      anchors: anchors,
      onSnapCommit: onSnapCommit,
      parent: buildParent(ancestor),
    );
  }

  @override
  Simulation? createBallisticSimulation(
    ScrollMetrics position,
    double velocity,
  ) {
    final natural = super.createBallisticSimulation(position, velocity);
    final target = _resolveTarget(position, velocity, natural);
    if (target == null) return natural;
    onSnapCommit?.call(target);
    return ScrollSpringSimulation(
      kSnapSpring,
      position.pixels,
      target,
      velocity,
      tolerance: toleranceFor(position),
    );
  }

  /// Resolves the clamped section-framed resting position, or `null` to keep
  /// the natural fling (header zone, free inside a tall section, already
  /// aligned, or no frames).
  double? _resolveTarget(
    ScrollMetrics position,
    double velocity,
    Simulation? natural,
  ) {
    final list = anchors.values;
    if (list.isEmpty) return null;
    // Let the platform overscroll own the hard edges. At the bottom of the feed
    // (notably under "Fin de tournée"), forcing our section spring on top of
    // iOS' bounce creates stepped rebounds and repeated settle haptics.
    if (position.outOfRange ||
        (position.pixels >= position.maxScrollExtent - kSnapEpsilon &&
            velocity >= 0)) {
      return null;
    }
    // Header/banner zone (above the first section) → let the RefreshIndicator
    // own pull-to-refresh; never snap.
    if (position.pixels <= list.first.top) return null;

    final landing =
        natural == null ? position.pixels : _simulationEndX(natural, position);
    if (landing <= 0) return null;

    // Travel direction from the controller, not the lift velocity: a slow
    // drag-to-read down ends at ≈ 0 velocity, which would misread as "going
    // up". Shared mapping with the drag-time feedforward via [_travelDirection].
    final scrollDirection = position is ScrollPosition
        ? _travelDirection(position.userScrollDirection)
        : 0.0;

    final raw = resolveSnapTarget(
      currentPixels: position.pixels,
      naturalLanding: landing,
      velocity: velocity,
      scrollDirection: scrollDirection,
      frames: list,
    );
    if (raw == null) return null;

    final clamped = raw.clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((clamped - position.pixels).abs() <= kSnapEpsilon) return null;
    return clamped;
  }
}

/// Estimates the resting position of a ballistic [sim] by sampling it forward
/// until it reports done (capped). Honours the platform deceleration baked into
/// [sim] rather than re-deriving a friction model.
double _simulationEndX(Simulation sim, ScrollMetrics position) {
  var last = position.pixels;
  for (var t = 0.0; t <= 10.0; t += 1 / 60) {
    final x = sim.x(t);
    if (x.isNaN) break;
    last = x;
    if (sim.isDone(t)) break;
  }
  return last;
}

/// (A3) « Carte haute = lecture libre » signifier. A section taller than the
/// viewport (its index is in [tallSections]) gets a subtle bottom fade
/// (`backgroundPrimary` → transparent, ~24 px), reading as « ce contenu coule
/// sous le bord, tu peux scroller librement » — coherent with the physics
/// leaving that interior un-snapped and with A1 emitting no « va snapper » dot
/// there. Short/snapping sections render the child untouched. Painted by the
/// screen (Stack overlay) so [SectionBlock]'s signature stays unchanged.
class _FreeReadEdgeFade extends StatelessWidget {
  final int index;
  final ValueListenable<Set<int>> tallSections;
  final Widget child;

  const _FreeReadEdgeFade({
    required this.index,
    required this.tallSections,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Set<int>>(
      valueListenable: tallSections,
      child: child,
      builder: (context, tall, child) {
        if (!tall.contains(index)) return child!;
        final base = context.facteurColors.backgroundPrimary;
        return Stack(
          children: [
            child!,
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              height: 24,
              child: IgnorePointer(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [base.withValues(alpha: 0), base],
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _StickyHostOverlay extends StatelessWidget {
  final ValueNotifier<bool> stickyVisible;
  final ValueNotifier<int> activeIndex;

  /// Descripteurs d'onglets (label+accent) dans l'ordre des slivers, calculés
  /// par [_FluxContinuScreenState._syncStickyEntries] — source unique partagée
  /// avec les clés du suivi actif, pour éviter tout recalcul divergent ici.
  final List<StickyTab> tabs;
  final ValueChanged<int> onTapTab;
  final ScrollController tabsController;
  final void Function(int oldIndex, int newIndex) onReorder;
  final VoidCallback onDragStart;
  final VoidCallback onDragEnd;

  const _StickyHostOverlay({
    required this.stickyVisible,
    required this.activeIndex,
    required this.tabs,
    required this.onTapTab,
    required this.tabsController,
    required this.onReorder,
    required this.onDragStart,
    required this.onDragEnd,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: ValueListenableBuilder<bool>(
        valueListenable: stickyVisible,
        builder: (context, visible, _) {
          final showSticky = visible && tabs.isNotEmpty;
          if (!showSticky) {
            return const SizedBox.shrink();
          }
          // The progress track is now segmented and driven solely by the
          // discrete active index — no continuous scroll-fraction needed.
          return ValueListenableBuilder<int>(
            valueListenable: activeIndex,
            builder: (context, idx, _) => StickyTabBar(
              tabs: tabs,
              activeIndex: idx.clamp(0, tabs.length - 1),
              onTapTab: onTapTab,
              tabsController: tabsController,
              showFilterBar: false,
              onReorder: onReorder,
              onDragStart: onDragStart,
              onDragEnd: onDragEnd,
            ),
          );
        },
      ),
    );
  }
}

/// Chrome partagée des pills de découvrabilité (drag des onglets,
/// pull-to-refresh) : capsule pleine à coins ronds + ombre douce, icône +
/// libellé. Seuls la couleur de fond/ombre, l'icône et le texte varient.
class _HintPill extends StatelessWidget {
  final Widget icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color shadowColor;

  const _HintPill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.shadowColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(FacteurRadius.full),
        boxShadow: [
          BoxShadow(
            color: shadowColor,
            blurRadius: 12,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          icon,
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: foreground,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Pill de découvrabilité du réordre par drag des onglets. Rendue une seule
/// fois (cf. [_kDragHintSeenKey]), juste sous la barre sticky.
class _HeaderDragHint extends StatelessWidget {
  const _HeaderDragHint();

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(top: _kStickyBarHeight + 10),
      child: Center(
        child: _HintPill(
          icon: Icon(
            PhosphorIcons.handGrabbing(PhosphorIconsStyle.bold),
            size: 14,
            color: colors.backgroundPrimary,
          ),
          label: 'Maintiens un onglet pour réorganiser ta tournée',
          background: colors.textPrimary.withValues(alpha: 0.92),
          foreground: colors.backgroundPrimary,
          shadowColor: const Color.fromRGBO(0, 0, 0, 0.18),
        ),
      ),
    );
  }
}

class _PullToRefreshHint extends StatefulWidget {
  final bool active;
  const _PullToRefreshHint({required this.active});

  @override
  State<_PullToRefreshHint> createState() => _PullToRefreshHintState();
}

class _PullToRefreshHintState extends State<_PullToRefreshHint>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bounceController;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    if (widget.active) _bounceController.repeat();
  }

  @override
  void didUpdateWidget(_PullToRefreshHint oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_bounceController.isAnimating) {
      _bounceController.repeat();
    } else if (!widget.active && _bounceController.isAnimating) {
      _bounceController.stop();
      _bounceController.value = 0;
    }
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.only(top: 80),
      child: Center(
        child: _HintPill(
          icon: AnimatedBuilder(
            animation: _bounceController,
            builder: (context, child) {
              final t = _bounceController.value;
              final offset = math.sin(t * math.pi * 2) * 3.0;
              return Transform.translate(
                offset: Offset(0, offset),
                child: child,
              );
            },
            child: Icon(
              PhosphorIcons.arrowDown(PhosphorIconsStyle.bold),
              size: 14,
              color: Colors.white,
            ),
          ),
          label: 'Tirer pour rafraîchir',
          background: colors.primary.withValues(alpha: 0.95),
          foreground: Colors.white,
          shadowColor: colors.primary.withValues(alpha: 0.25),
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final Object error;
  final Future<void> Function() onRetry;

  const _ErrorView({required this.error, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(FacteurSpacing.space8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.cloud_off_rounded, size: 48, color: colors.textTertiary),
            const SizedBox(height: FacteurSpacing.space3),
            Text(
              'Le flux continu est indisponible.',
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: colors.textSecondary),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: FacteurSpacing.space4),
            OutlinedButton(onPressed: onRetry, child: const Text('Réessayer')),
          ],
        ),
      ),
    );
  }
}

class _EmptySectionsHint extends StatelessWidget {
  final Future<void> Function() onRetry;
  const _EmptySectionsHint({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final colors = context.facteurColors;
    return Padding(
      padding: const EdgeInsets.all(FacteurSpacing.space6),
      child: Column(
        children: [
          Icon(Icons.inbox_outlined, size: 36, color: colors.textTertiary),
          const SizedBox(height: 8),
          Text(
            'Pas encore de contenu pour la tournée du jour.',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: colors.textSecondary),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 12),
          TextButton(onPressed: onRetry, child: const Text('Recharger')),
        ],
      ),
    );
  }
}
