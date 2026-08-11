import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/analytics_provider.dart';
import '../repositories/essentiel_repository.dart';
import '../services/tournee_progress_service.dart';
import 'essentiel_extra_articles_provider.dart';

/// Issue d'un geste de tri. Volontairement disjointe des actions d'interaction
/// existantes : `pass` n'est **pas** `not_interested` (qui mute la source
/// entière, sans expiration) et `keep` n'est **pas** `read` (qui appliquerait
/// `_W_READ_PENALTY` côté backend et ferait disparaître de la carte l'article
/// qu'on vient de choisir). Cf. Story 33.1, pièges n°1 et n°2.
enum TriageDecision {
  keep('keep'),
  later('later'),
  pass('pass');

  const TriageDecision(this.wire);

  /// Valeur envoyée au backend (`essentiel_triage_decisions.decision`).
  final String wire;

  static TriageDecision? fromWire(String? value) {
    for (final d in TriageDecision.values) {
      if (d.wire == value) return d;
    }
    return null;
  }
}

/// Modalité du geste — sépare le swipe du mode boutons (accessibilité). Un
/// écart fort entre les deux en dit plus sur le geste que sur l'article.
enum TriageVia {
  swipe('swipe'),
  button('button'),

  /// La carte du dessus a été **tapée**, l'article ouvert, et lu : au retour la
  /// lecture vaut « Je garde » (Story 33.2). Aucune décision n'est prise au tap
  /// lui-même — seul le retour d'une lecture effective décide.
  read('read');

  const TriageVia(this.wire);

  final String wire;

  /// Repli sur [swipe] : la valeur historique, et la seule qui existait avant
  /// que le champ ne soit sérialisé en multi-valeurs.
  static TriageVia fromWire(String? value) {
    for (final v in TriageVia.values) {
      if (v.wire == value) return v;
    }
    return TriageVia.swipe;
  }
}

/// Une décision prise, en attente d'envoi.
@immutable
class TriageEntry {
  final String contentId;
  final TriageDecision decision;

  /// Rang **dans le slate figé** (1-indexé), pas dans le re-rank courant.
  final int rank;
  final TriageVia via;
  final int? latencyMs;

  const TriageEntry({
    required this.contentId,
    required this.decision,
    required this.rank,
    required this.via,
    this.latencyMs,
  });

  Map<String, dynamic> toJson() => {
        'content_id': contentId,
        'decision': decision.wire,
        'rank': rank,
        'decided_via': via.wire,
        if (latencyMs != null) 'latency_ms': latencyMs,
      };

  static TriageEntry? fromJson(Map<String, dynamic> json) {
    final contentId = json['content_id'];
    final decision = TriageDecision.fromWire(json['decision'] as String?);
    final rank = json['rank'];
    if (contentId is! String || decision == null || rank is! int) return null;
    return TriageEntry(
      contentId: contentId,
      decision: decision,
      rank: rank,
      via: TriageVia.fromWire(json['decided_via'] as String?),
      latencyMs: json['latency_ms'] as int?,
    );
  }
}

/// Machine d'état du tri du jour.
///
/// Le **préfixe du slate est figé** : une fois le premier geste posé, l'ordre
/// des articles déjà proposés ne bouge plus de la journée. C'est un recul
/// assumé sur la story 9.8 (« L'Essentiel vivant au retour », où
/// `GET /api/essentiel` re-ranke à chaque requête) : sans ce gel, un refetch en
/// cours de tri changerait la pile sous le doigt. Le re-rank reprend la main le
/// lendemain.
///
/// Ce que la story 33.4 change : le slate n'est plus **coupé** à la cible. Il
/// porte tout le pool proposé et s'allonge en queue à mesure que le pool
/// s'élargit ([EssentielTriageNotifier.syncSlate]). Ce qui borne le tri n'est
/// plus sa taille mais [goal] — le nombre d'articles à **garder**.
@immutable
class EssentielTriageState {
  /// Clé du jour (`TourneeProgressService.dayKey`, bascule 07h30 Paris).
  final String dayKey;

  /// Ordre gelé des `contentId`, **croissant** : tout le pool déjà proposé.
  /// Vide ⇒ le tri n'a jamais commencé.
  final List<String> slate;

  final Map<String, TriageEntry> decisions;

  /// Objectif du jour réglé au stepper (« Garder − N + articles »), persisté
  /// dans le blob jour : le nombre d'articles à
  /// **garder**, jamais la taille du slate. `null` ⇒ jamais touché
  /// ([kTriageGoalDefault]).
  ///
  /// Peut dépasser [kTriageGoalMax] : ce plafond ne borne que le stepper, pas
  /// « Plus d'articles ? » ([EssentielTriageNotifier.extendGoal]).
  final int? goal;

  /// L'utilisateur a arrêté son tri via le nudge « tu peux t'arrêter là »,
  /// avant d'avoir atteint [goal]. Termine le tri sur les gardés obtenus.
  final bool stopped;

  /// Il a fermé ce nudge sans arrêter — il ne doit pas revenir au remontage.
  final bool stopNudgeDismissed;

  /// `true` une fois l'état restauré depuis SharedPreferences — évite de rendre
  /// la pile puis de la faire disparaître au cold-boot.
  final bool hydrated;

  const EssentielTriageState({
    required this.dayKey,
    this.slate = const [],
    this.decisions = const {},
    this.goal,
    this.stopped = false,
    this.stopNudgeDismissed = false,
    this.hydrated = false,
  });

  const EssentielTriageState.empty()
      : dayKey = '',
        slate = const [],
        decisions = const {},
        goal = null,
        stopped = false,
        stopNudgeDismissed = false,
        hydrated = false;

  bool get hasStarted => slate.isNotEmpty;

  /// Position du prochain article à trier, ou `slate.length` si tout est trié.
  int get index {
    for (var i = 0; i < slate.length; i++) {
      if (!decisions.containsKey(slate[i])) return i;
    }
    return slate.length;
  }

  /// Cible **effective** de gardés.
  ///
  /// [kTriageGoalMax] ne borne que le stepper : « Plus d'articles ? »
  /// ([EssentielTriageNotifier.extendGoal]) a le droit de le dépasser, et la
  /// valeur dépassée doit rester la cible réelle — d'où le `max`, qui laisse
  /// passer un [goal] au-dessus du plafond tout en gardant le plancher.
  int get effectiveGoal => math.max(effectiveTriageGoal(goal), goal ?? 0);

  bool get goalReached => keptCount >= effectiveGoal;

  /// Plus rien à proposer : le pool a été trié en entier.
  bool get poolExhausted => index >= slate.length;

  /// Le tri est fini — cible atteinte, pool épuisé, ou arrêt volontaire. Les
  /// trois sorties rendent le même écran de fin ; seule la jauge les distingue
  /// (`ended_by`).
  bool get done => hasStarted && (stopped || goalReached || poolExhausted);

  /// La carte doit-elle rendre la pile plutôt que la liste passive ?
  bool get isActive => hydrated && hasStarted && !done;

  /// `contentId` du haut de la pile, `null` si le tri est fini.
  String? get currentContentId => index < slate.length ? slate[index] : null;

  /// Articles gardés, **dans l'ordre du slate**. `later` compte comme gardé :
  /// mettre de côté est un choix positif, pas un rejet (décision PO, reconduite
  /// en 33.4 — un `later` fait donc avancer la cible comme un `keep`).
  List<String> get keptContentIds => [
        for (final id in slate)
          if (decisions[id]?.decision == TriageDecision.keep ||
              decisions[id]?.decision == TriageDecision.later)
            id,
      ];

  int get keptCount => keptContentIds.length;

  int get passedCount =>
      decisions.values.where((e) => e.decision == TriageDecision.pass).length;

  int get laterCount =>
      decisions.values.where((e) => e.decision == TriageDecision.later).length;

  /// Refus (`pass`) enchaînés **juste avant** le haut de pile — le signal du
  /// nudge « tu peux t'arrêter là ».
  ///
  /// Dérivé du slate, sans champ persisté : il se réinitialise seul dès qu'un
  /// article est gardé (le `keep` casse la chaîne) et survit au cold-boot sans
  /// stockage dédié, puisque l'ordre est déjà porté par le slate.
  int get consecutivePassCount {
    var n = 0;
    for (var i = index - 1; i >= 0; i--) {
      if (decisions[slate[i]]?.decision != TriageDecision.pass) break;
      n++;
    }
    return n;
  }

  EssentielTriageState copyWith({
    String? dayKey,
    List<String>? slate,
    Map<String, TriageEntry>? decisions,
    int? goal,
    bool? stopped,
    bool? stopNudgeDismissed,
    bool? hydrated,
  }) =>
      EssentielTriageState(
        dayKey: dayKey ?? this.dayKey,
        slate: slate ?? this.slate,
        decisions: decisions ?? this.decisions,
        goal: goal ?? this.goal,
        stopped: stopped ?? this.stopped,
        stopNudgeDismissed: stopNudgeDismissed ?? this.stopNudgeDismissed,
        hydrated: hydrated ?? this.hydrated,
      );

  Map<String, dynamic> toJson() => {
        'day_key': dayKey,
        'slate': slate,
        'decisions': decisions.values.map((e) => e.toJson()).toList(),
        if (goal != null) 'goal': goal,
        if (stopped) 'stopped': true,
        if (stopNudgeDismissed) 'stop_nudge_dismissed': true,
      };
}

/// Clé du blob jour. **v2** (33.4) : les blobs `v1` portaient `target` = *taille
/// de slate*. Le relire comme un objectif de gardés donnerait des cibles fausses
/// (un `target: 7` deviendrait « garde 7 articles »), d'où le bump plutôt qu'une
/// migration en place. Les clés `v1` sont purgées au premier démarrage.
const String kTriagePrefsKeyPrefix = 'essentiel_triage_v2_';

/// Ancien préfixe, purgé en une fois par [EssentielTriageNotifier]. Coût
/// assumé : un tri en cours le jour du déploiement repart à zéro — c'est l'état
/// d'une journée, et le lendemain la question ne se pose plus.
const String kTriageLegacyPrefsKeyPrefix = 'essentiel_triage_v1_';

String triagePrefsKey(String dayKey) => '$kTriagePrefsKeyPrefix$dayKey';

/// Délai de regroupement des envois. Le tri ne doit **jamais** attendre le
/// réseau : les décisions partent en fire-and-forget batché, et un flush forcé
/// couvre la fin de tri et le passage en arrière-plan.
const Duration kTriageFlushDebounce = Duration(seconds: 2);

/// Objectif par défaut du tri du jour — la doctrine du digest à 5 articles,
/// inchangée. Ce qui change en 33.4 : c'est un nombre d'articles à **garder**,
/// plus une taille de slate.
const int kTriageGoalDefault = 5;

/// Plancher de l'objectif réglable.
const int kTriageGoalMin = 3;

/// Plafond du **stepper**. « Plus d'articles ? » peut le dépasser
/// ([EssentielTriageNotifier.extendGoal]) : c'est la sortie « exceptionnellement
/// j'en veux plus », elle ne doit pas buter sur le réglage courant.
const int kTriageGoalMax = 10;

/// Ce que « Plus d'articles ? » ajoute à l'objectif — « Deux de plus », le
/// libellé du CTA.
const int kTriageGoalExtendStep = 2;

/// Nombre de refus enchaînés à partir duquel on propose d'arrêter le tri
/// (décision PO). En deçà, un utilisateur qui écarte trois papiers fait
/// simplement son travail de tri.
const int kTriageStopNudgeThreshold = 5;

/// Objectif **effectif** du stepper : [goal] s'il a été touché, sinon
/// [kTriageGoalDefault], borné à `[kTriageGoalMin, kTriageGoalMax]`.
/// Arithmétique pure — ne dépend **plus** du pool, et c'est tout le changement
/// de la 33.4 : c'est cette dépendance qui rendait le slate et l'objectif
/// indissociables.
int effectiveTriageGoal(int? goal) =>
    (goal ?? kTriageGoalDefault).clamp(kTriageGoalMin, kTriageGoalMax);

class EssentielTriageNotifier extends StateNotifier<EssentielTriageState> {
  /// [initialState] court-circuite l'hydratation SharedPreferences. Réservé aux
  /// tests : sans lui, l'hydratation asynchrone rend le rendu de la carte
  /// dépendant du nombre de frames pompées, ce qui fait passer ou échouer les
  /// tests de la carte par accident de timing plutôt que par intention.
  EssentielTriageNotifier(
    this._ref, {
    DateTime? now,
    @visibleForTesting EssentielTriageState? initialState,
  })  : _dayKey = TourneeProgressService.dayKey(now ?? DateTime.now()),
        super(const EssentielTriageState.empty()) {
    if (initialState != null) {
      state = initialState;
      return;
    }
    state = EssentielTriageState(dayKey: _dayKey);
    unawaited(_hydrate());
  }

  final Ref _ref;
  final String _dayKey;

  Timer? _flushTimer;

  /// Décisions pas encore acquittées par le backend. Ré-émises tant qu'un envoi
  /// n'a pas abouti : une décision perdue est une ligne manquante dans la jauge.
  final Map<String, TriageEntry> _pending = {};

  /// Horodatage du moment où l'article du dessus est devenu visible — sert à
  /// calculer `latency_ms` (détection du tri distrait).
  DateTime? _shownAt;

  int? _sessionStartMs;

  @visibleForTesting
  Map<String, TriageEntry> get pendingForTest => Map.unmodifiable(_pending);

  @override
  void dispose() {
    _flushTimer?.cancel();
    super.dispose();
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await _purgeStaleKeys(prefs);
      final raw = prefs.getString(triagePrefsKey(_dayKey));
      if (raw == null) {
        state = state.copyWith(hydrated: true);
        return;
      }
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        state = state.copyWith(hydrated: true);
        return;
      }
      final slate = (decoded['slate'] as List?)?.whereType<String>().toList() ??
          const <String>[];
      final entries = <String, TriageEntry>{};
      for (final item in (decoded['decisions'] as List?) ?? const []) {
        if (item is Map<String, dynamic>) {
          final entry = TriageEntry.fromJson(item);
          if (entry != null) entries[entry.contentId] = entry;
        }
      }
      final goal = decoded['goal'];
      state = state.copyWith(
        slate: slate,
        decisions: entries,
        goal: goal is int ? goal : null,
        stopped: decoded['stopped'] == true,
        stopNudgeDismissed: decoded['stop_nudge_dismissed'] == true,
        hydrated: true,
      );
    } catch (e) {
      debugPrint('EssentielTriage: hydrate failed: $e');
      state = state.copyWith(hydrated: true);
    }
  }

  /// Purge les clés des jours précédents — sans quoi elles s'accumuleraient
  /// indéfiniment dans SharedPreferences (même motif que
  /// `TourneeProgressService.purgeOldPrefsKeys`) — **et** la totalité des clés
  /// `v1`, dont le champ `target` ne veut plus dire la même chose (33.4).
  Future<void> _purgeStaleKeys(SharedPreferences prefs) async {
    await TourneeProgressService.purgeDatedPrefsKeys(
      prefs,
      prefix: kTriagePrefsKeyPrefix,
      keep: triagePrefsKey(_dayKey),
    );
    // `keep: ''` ⇒ aucune clé conservée : le format v1 n'a plus de lecteur.
    await TourneeProgressService.purgeDatedPrefsKeys(
      prefs,
      prefix: kTriageLegacyPrefsKeyPrefix,
      keep: '',
    );
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        triagePrefsKey(_dayKey),
        jsonEncode(state.toJson()),
      );
    } catch (e) {
      debugPrint('EssentielTriage: persist failed: $e');
    }
  }

  /// Aligne le slate sur le pool adressable ([poolIds] = slate servi par
  /// `GET /api/essentiel`, puis articles injectables du carrousel, puis
  /// articles rapatriés au réseau — c'est l'appelant qui passe le pool ordonné).
  ///
  /// - **Premier appel** : gèle l'ordre du pool tel quel. Plus aucun `take` :
  ///   la cible ([goal]) ne borne plus le slate, elle borne les *gardés*.
  /// - **Appels suivants** : **append en queue** de tout id du pool absent du
  ///   slate. Le préfixe n'est jamais réordonné ni raccourci ⇒ rien de ce qui
  ///   est déjà affiché ne bouge, et l'opération est idempotente.
  ///
  /// C'est ce qui remplace la réconciliation cold-boot de la 33.3 (le carrousel
  /// arrivant après le héros) : un pool partiel devient un slate partiel qui
  /// s'allonge de lui-même dès que le reste arrive.
  void syncSlate(List<String> poolIds) {
    if (poolIds.isEmpty) return;
    if (!state.hasStarted) {
      _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
      _shownAt = DateTime.now();
      final seen = <String>{};
      state = state.copyWith(
        slate: List.unmodifiable([
          for (final id in poolIds)
            if (seen.add(id)) id,
        ]),
      );
      unawaited(_persist());
      return;
    }

    final seen = state.slate.toSet();
    final appended = [
      for (final id in poolIds)
        if (seen.add(id)) id,
    ];
    if (appended.isEmpty) return;
    // La pile était à sec : les ajouts la rouvrent, la mesure de latence
    // repart du moment où la nouvelle carte du dessus devient visible.
    if (state.poolExhausted) _shownAt = DateTime.now();
    state = state.copyWith(
      slate: List.unmodifiable([...state.slate, ...appended]),
    );
    unawaited(_persist());
  }

  /// Marque l'article du dessus comme affiché — point de départ de la mesure de
  /// latence.
  void markShown() => _shownAt = DateTime.now();

  void decide(TriageDecision decision, {required TriageVia via}) {
    final contentId = state.currentContentId;
    if (contentId == null) return;

    final rank = state.index + 1;
    final shownAt = _shownAt;
    final entry = TriageEntry(
      contentId: contentId,
      decision: decision,
      rank: rank,
      via: via,
      latencyMs: shownAt == null
          ? null
          : DateTime.now().difference(shownAt).inMilliseconds,
    );

    state = state.copyWith(
      decisions: {...state.decisions, contentId: entry},
    );
    _shownAt = DateTime.now();
    _pending[contentId] = entry;

    unawaited(_persist());
    unawaited(_ref.read(analyticsServiceProvider).trackEssentielTriage(
          decision: decision.wire,
          contentId: contentId,
          rank: rank,
          slateSize: state.slate.length,
          goal: state.effectiveGoal,
          decidedVia: via.wire,
          latencyMs: entry.latencyMs,
        ));

    if (state.done) {
      _trackSessionEnd();
      unawaited(flush());
    } else {
      _scheduleFlush();
    }
  }

  /// « Refaire ? » — le slate reste **le même** (son ordre est figé pour la
  /// journée), seules les décisions repartent à zéro, ainsi que l'arrêt
  /// volontaire et le nudge qui le propose. Le backend écrase par upsert sur
  /// `(user, content, jour)`.
  void restart() {
    if (!state.hasStarted) return;
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _shownAt = DateTime.now();
    state = state.copyWith(
      decisions: const {},
      stopped: false,
      stopNudgeDismissed: false,
    );
    unawaited(_persist());
  }

  /// Règle l'objectif du jour à [n] articles **à garder** — le levier du
  /// stepper « Garder − N + articles ».
  ///
  /// Ne touche **plus au slate du tout** : c'est tout l'intérêt de la 33.4.
  /// Baisser la cible ne détruit donc rien, et la contrainte « ne jamais
  /// retirer un article décidé » devient sans objet. Si `n <= keptCount`, le
  /// tri devient `done` dans la frame : c'est le comportement voulu
  /// (« finalement 3 me suffisent »).
  ///
  /// [n] est borné à `[kTriageGoalMin, kTriageGoalMax]` — le stepper est le
  /// réglage courant, pas la sortie exceptionnelle ([extendGoal]).
  void setGoal(int n) {
    final wanted = n.clamp(kTriageGoalMin, kTriageGoalMax);
    if (state.goal == wanted) return;
    state = state.copyWith(goal: wanted);
    unawaited(_persist());
  }

  /// « Plus d'articles ? » — pousse l'objectif de [delta] gardés de plus, **sans
  /// plafond haut** ([kTriageGoalMax] ne borne que le stepper), et lève un arrêt
  /// volontaire éventuel.
  ///
  /// Synchrone : la pile rouvre dans la frame si le slate a de quoi tenir la
  /// nouvelle cible. Sinon le prefetch automatique de la carte s'en charge.
  void extendGoal(int delta) {
    if (delta <= 0) return;
    final reopens = state.done;
    state = state.copyWith(
      goal: state.effectiveGoal + delta,
      stopped: false,
    );
    if (reopens) {
      // Nouvelle fenêtre de tri : session et latence repartent, comme à
      // l'ouverture de la pile.
      _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
      _shownAt = DateTime.now();
    }
    unawaited(_persist());
  }

  /// « Arrêter le tri » depuis le nudge : termine la journée sur les gardés
  /// obtenus, même en deçà de l'objectif. Ce n'est pas un échec — la fin de tri
  /// n'affiche plus l'objectif (33.4).
  void stopTriage() {
    if (!state.hasStarted || state.stopped) return;
    state = state.copyWith(stopped: true);
    unawaited(_persist());
    _trackStopNudge('accepted');
    _trackSessionEnd();
    unawaited(flush());
  }

  /// Croix du nudge : il ne revient plus de la journée (persisté dans le blob
  /// jour ⇒ pas de réapparition au remontage).
  void dismissStopNudge() {
    if (state.stopNudgeDismissed) return;
    state = state.copyWith(stopNudgeDismissed: true);
    unawaited(_persist());
    _trackStopNudge('dismissed');
  }

  /// Le nudge vient d'apparaître — mesuré depuis la pile, un seul point d'entrée
  /// pour les trois actions de l'event.
  void trackStopNudgeShown() => _trackStopNudge('shown');

  void _trackStopNudge(String action) {
    unawaited(_ref.read(analyticsServiceProvider).trackEssentielTriageStopNudge(
          action: action,
          consecutivePass: state.consecutivePassCount,
          keptCount: state.keptCount,
          goal: state.effectiveGoal,
        ));
  }

  /// Retire du slate figé les articles **non décidés** qui ne se résolvent plus
  /// dans le pool adressable par la carte ([availableIds] = slate du jour +
  /// articles du carrousel injectables).
  ///
  /// Sans ça, un slate qui référence un article disparu **fige la carte sur un
  /// corps vide** : `EssentielTriageStack` ne sait pas rendre le haut de pile et
  /// sortait en `SizedBox.shrink()` (l'aplat beige rapporté par le PO). Les
  /// chemins qui y mènent sont réels et persistants :
  ///
  /// - [syncSlate] persiste des `contentId` **du carrousel du jour** ; au
  ///   cold-boot suivant, l'hydratation depuis le cache ne porte pas de
  ///   carrousel → ces ids ne sont dans aucun pool ;
  /// - le blend live (story 9.8) peut renvoyer un jeu d'articles différent du
  ///   slate gelé le matin ;
  /// - tous les articles de l'Essentiel masqués au swipe.
  ///
  /// Les ids **déjà décidés** sont conservés : leur décision est partie au
  /// backend, et le rendu des gardés est déjà gardé par la résolution dans le
  /// pool. L'opération est strictement décroissante ⇒ l'appelant peut la
  /// rejouer sans risque de boucle. Slate vidé ⇒ [hasStarted] redevient faux et
  /// [syncSlate] re-gèle sur les articles du jour.
  ///
  /// Ne peut pas non plus boucler **contre** [syncSlate] : celle-ci n'append que
  /// des ids **présents** dans le pool, celle-ci ne retire que des ids
  /// **absents** du pool — les deux ne peuvent pas se contredire sur le même id.
  void pruneUnavailable(Set<String> availableIds) {
    if (!state.hasStarted || availableIds.isEmpty) return;
    final kept = [
      for (final id in state.slate)
        if (availableIds.contains(id) || state.decisions.containsKey(id)) id,
    ];
    if (kept.length == state.slate.length) return;
    state = state.copyWith(
      slate: List.unmodifiable(kept),
      // L'objectif est volontairement conservé : il ne dépend plus du slate
      // (33.4), donc un pool momentanément incomplet ne peut plus le fausser.
    );
    unawaited(_persist());
  }

  void _trackSessionEnd() {
    final startedMs = _sessionStartMs;
    // Trois sorties, un seul écran de fin — mais la jauge doit les distinguer :
    // c'est `ended_by == 'exhausted'` qui dira si la pile sèche avant la cible,
    // donc si l'élargissement du pool `/more` a suffi.
    final endedBy = state.stopped
        ? 'stopped'
        : state.goalReached
            ? 'goal'
            : 'exhausted';
    unawaited(_ref.read(analyticsServiceProvider).trackEssentielTriageSession(
          slateSize: state.slate.length,
          goal: state.effectiveGoal,
          goalReached: state.goalReached,
          endedBy: endedBy,
          autoFetches:
              _ref.read(essentielExtraArticlesProvider.notifier).autoFetchCount,
          kept: state.keptCount - state.laterCount,
          later: state.laterCount,
          passed: state.passedCount,
          durationMs: startedMs == null
              ? null
              : DateTime.now().millisecondsSinceEpoch - startedMs,
        ));
  }

  void _scheduleFlush() {
    _flushTimer?.cancel();
    _flushTimer = Timer(kTriageFlushDebounce, () => unawaited(flush()));
  }

  /// Envoie les décisions en attente. Appelé au debounce, à la fin du tri et au
  /// passage en arrière-plan. Les décisions restent en attente si l'envoi
  /// échoue — elles repartiront au prochain flush.
  Future<void> flush() async {
    _flushTimer?.cancel();
    if (_pending.isEmpty || !state.hasStarted) return;

    final batch = List<TriageEntry>.from(_pending.values);
    final ok = await _ref.read(essentielRepositoryProvider).postTriage(
          digestDate: state.dayKey,
          slateSize: state.slate.length,
          decisions: batch.map((e) => e.toJson()).toList(),
        );
    if (!ok) return;

    for (final entry in batch) {
      // Ne retire que ce qui a été envoyé : une décision révisée entre-temps
      // doit repartir au tour suivant.
      if (identical(_pending[entry.contentId], entry)) {
        _pending.remove(entry.contentId);
      }
    }
  }
}

final essentielTriageProvider =
    StateNotifierProvider<EssentielTriageNotifier, EssentielTriageState>(
  (ref) => EssentielTriageNotifier(ref),
);
