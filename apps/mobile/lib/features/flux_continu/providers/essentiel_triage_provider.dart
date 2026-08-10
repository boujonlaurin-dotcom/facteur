import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../core/providers/analytics_provider.dart';
import '../repositories/essentiel_repository.dart';
import '../services/tournee_progress_service.dart';

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
/// Le **slate est figé** : une fois le premier geste posé, l'ordre des articles
/// ne bouge plus de la journée. C'est un recul assumé sur la story 9.8
/// (« L'Essentiel vivant au retour », où `GET /api/essentiel` re-ranke à chaque
/// requête) : sans ce gel, un refetch en cours de tri changerait la pile sous le
/// doigt et la barre de progression mentirait. Le re-rank reprend la main le
/// lendemain.
@immutable
class EssentielTriageState {
  /// Clé du jour (`TourneeProgressService.dayKey`, bascule 07h30 Paris).
  final String dayKey;

  /// Ordre gelé des `contentId`. Vide ⇒ le tri n'a jamais commencé.
  final List<String> slate;

  final Map<String, TriageEntry> decisions;

  /// Cible du jour réglée au stepper (« − N + articles aujourd'hui »),
  /// persistée dans le blob jour. `null` ⇒ jamais touchée : le gel prend le
  /// défaut ([kTriageTargetDefault] borné au pool). Une fois publiée, elle vaut
  /// la taille choisie. Elle peut temporairement dépasser le slate si le héros
  /// est restauré avant le carrousel ; la réconciliation complète le slate à
  /// mesure que le pool revient. Après une baisse manuelle, elle reprend la
  /// taille réelle (la baisse peut s'arrêter sur un article déjà décidé).
  final int? target;

  /// `true` une fois l'état restauré depuis SharedPreferences — évite de rendre
  /// la pile puis de la faire disparaître au cold-boot.
  final bool hydrated;

  const EssentielTriageState({
    required this.dayKey,
    this.slate = const [],
    this.decisions = const {},
    this.target,
    this.hydrated = false,
  });

  const EssentielTriageState.empty()
      : dayKey = '',
        slate = const [],
        decisions = const {},
        target = null,
        hydrated = false;

  bool get hasStarted => slate.isNotEmpty;

  /// Position du prochain article à trier, ou `slate.length` si tout est trié.
  int get index {
    for (var i = 0; i < slate.length; i++) {
      if (!decisions.containsKey(slate[i])) return i;
    }
    return slate.length;
  }

  bool get done => hasStarted && index >= slate.length;

  /// La carte doit-elle rendre la pile plutôt que la liste passive ?
  bool get isActive => hydrated && hasStarted && !done;

  /// `contentId` du haut de la pile, `null` si le tri est fini.
  String? get currentContentId => index < slate.length ? slate[index] : null;

  /// Articles gardés, **dans l'ordre du slate**. `later` compte comme gardé :
  /// mettre de côté est un choix positif, pas un rejet.
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

  EssentielTriageState copyWith({
    String? dayKey,
    List<String>? slate,
    Map<String, TriageEntry>? decisions,
    int? target,
    bool? hydrated,
  }) =>
      EssentielTriageState(
        dayKey: dayKey ?? this.dayKey,
        slate: slate ?? this.slate,
        decisions: decisions ?? this.decisions,
        target: target ?? this.target,
        hydrated: hydrated ?? this.hydrated,
      );

  Map<String, dynamic> toJson() => {
        'day_key': dayKey,
        'slate': slate,
        'decisions': decisions.values.map((e) => e.toJson()).toList(),
        if (target != null) 'target': target,
      };
}

const String kTriagePrefsKeyPrefix = 'essentiel_triage_v1_';

String triagePrefsKey(String dayKey) => '$kTriagePrefsKeyPrefix$dayKey';

/// Délai de regroupement des envois. Le tri ne doit **jamais** attendre le
/// réseau : les décisions partent en fire-and-forget batché, et un flush forcé
/// couvre la fin de tri et le passage en arrière-plan.
const Duration kTriageFlushDebounce = Duration(seconds: 2);

/// Cible par défaut du tri du jour — la doctrine du digest à 5 articles.
/// N'est qu'un point de départ : le stepper (« − N + articles aujourd'hui »)
/// la règle, et [effectiveTriageTarget] la borne au pool réellement adressable.
const int kTriageTargetDefault = 5;

/// Plancher de la cible réglable. En dessous, la pile n'est plus un tri : c'est
/// le pool lui-même qui borne quand il porte moins de 3 articles.
const int kTriageTargetMin = 3;

/// Cible **effective** du jour : [target] si le stepper a été touché, sinon
/// [kTriageTargetDefault] — dans les deux cas bornée à ce que le pool permet
/// (`[min(kTriageTargetMin, poolLength), poolLength]`). Arithmétique pure,
/// partagée entre le gel du slate ([EssentielTriageNotifier.startIfNeeded]) et
/// le stepper de l'en-tête, qui doivent annoncer le même nombre.
int effectiveTriageTarget(int? target, int poolLength) {
  if (poolLength <= 0) return 0;
  final lo = math.min(kTriageTargetMin, poolLength);
  final base = target ?? math.min(kTriageTargetDefault, poolLength);
  return base.clamp(lo, poolLength);
}

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
      final target = decoded['target'];
      state = state.copyWith(
        slate: slate,
        decisions: entries,
        target: target is int ? target : null,
        hydrated: true,
      );
    } catch (e) {
      debugPrint('EssentielTriage: hydrate failed: $e');
      state = state.copyWith(hydrated: true);
    }
  }

  /// Purge les clés des jours précédents — sans quoi elles s'accumuleraient
  /// indéfiniment dans SharedPreferences (même motif que
  /// `TourneeProgressService.purgeOldPrefsKeys`).
  Future<void> _purgeStaleKeys(SharedPreferences prefs) =>
      TourneeProgressService.purgeDatedPrefsKeys(
        prefs,
        prefix: kTriagePrefsKeyPrefix,
        keep: triagePrefsKey(_dayKey),
      );

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

  /// Fige le slate à la première frame de la pile, sur les
  /// [effectiveTriageTarget] **premiers** ids du pool adressable ([poolIds] =
  /// slate servi par `GET /api/essentiel` **suivi** des articles injectables du
  /// carrousel — c'est l'appelant qui passe le pool, pas seulement les 5).
  /// Si le tri a déjà commencé, l'ordre existant reste figé. Seule exception :
  /// une cible persistée plus grande que le slate momentanément disponible est
  /// réconciliée quand le reste du pool revient (cold-boot avant carrousel).
  void startIfNeeded(List<String> poolIds) {
    if (poolIds.isEmpty) return;
    if (state.hasStarted) {
      final wanted = effectiveTriageTarget(state.target, poolIds.length);
      if (state.slate.length < wanted) {
        final slate = List<String>.from(state.slate);
        final existing = slate.toSet();
        for (final id in poolIds) {
          if (slate.length >= wanted) break;
          if (existing.add(id)) slate.add(id);
        }
        if (slate.length == state.slate.length) return;
        _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
        _shownAt = DateTime.now();
        state = state.copyWith(
          slate: List.unmodifiable(slate),
          // Ne pas publier `wanted` comme nouvelle cible : il peut n'être que
          // la borne d'un pool encore partiel. La préférence restaurée (p. ex.
          // 10) doit survivre aux étapes intermédiaires (5, puis 7, puis 10).
        );
        unawaited(_persist());
      }
      return;
    }
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _shownAt = DateTime.now();
    final count = effectiveTriageTarget(state.target, poolIds.length);
    state = state.copyWith(
      slate: List.unmodifiable(poolIds.take(count)),
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

  /// « Trier à nouveau » — le slate reste **le même** (il est figé pour la
  /// journée), seules les décisions repartent à zéro. Le backend écrase par
  /// upsert sur `(user, content, jour)`.
  void restart() {
    if (!state.hasStarted) return;
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _shownAt = DateTime.now();
    state = state.copyWith(decisions: const {});
    unawaited(_persist());
  }

  /// Règle la cible du jour à [n] articles — le levier unique du stepper de
  /// l'en-tête **et** de « Plus d'articles ? » au tri terminé (qui appelle
  /// `setTarget(target + 2, poolIds)`).
  ///
  /// - **Hausse** : ajoute en fin de slate les ids du pool absents du slate,
  ///   jusqu'à [n]. La pile se **rouvre** d'elle-même : `index` repointe sur le
  ///   premier ajout non décidé, donc `done` redevient faux et `isActive` vrai.
  /// - **Baisse** : retire les ids **non décidés** en **fin** de slate jusqu'à
  ///   [n], et s'arrête dès qu'un décidé est en queue — jamais de décision
  ///   perdue (contrainte PO).
  ///
  /// [n] est borné à `[min(kTriageTargetMin, pool), pool]`. La cible publiée
  /// ([EssentielTriageState.target]) est la taille **réelle** du slate après
  /// l'opération, persistée sous la même clé jour (survit au cold-boot). Le
  /// slate reste **figé** au sens de la story : l'ordre existant ne bouge pas,
  /// on allonge ou raccourcit la queue. Les décisions envoyées ensuite portent
  /// le `slate_size` courant (via [decide]), ce qui garde `rank ≤ slate_size`
  /// côté backend.
  void setTarget(int n, List<String> poolIds) {
    if (!state.hasStarted) return;
    final hi = math.max(poolIds.length, state.slate.length);
    final lo = math.min(kTriageTargetMin, hi);
    final wanted = n.clamp(lo, hi);

    final slate = List<String>.from(state.slate);
    if (wanted > slate.length) {
      final existing = slate.toSet();
      for (final id in poolIds) {
        if (slate.length >= wanted) break;
        if (existing.add(id)) slate.add(id);
      }
    } else {
      while (
          slate.length > wanted && !state.decisions.containsKey(slate.last)) {
        slate.removeLast();
      }
    }

    final grew = slate.length > state.slate.length;
    if (grew) {
      // La pile rouvre sur les ajouts : nouvelle fenêtre de session, nouvelle
      // mesure de latence — même règle que l'ancien « Voir d'autres articles ».
      _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
      _shownAt = DateTime.now();
    }
    state = state.copyWith(
      slate: List.unmodifiable(slate),
      // Republie la taille réelle : une baisse arrêtée sur un décidé publie où
      // elle s'est vraiment arrêtée, pas le n demandé.
      target: slate.length,
    );
    unawaited(_persist());
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
  /// - « Plus d'articles » ([setTarget]) persiste des `contentId` **du
  ///   carrousel du jour** ; au cold-boot suivant, l'hydratation depuis le cache
  ///   ne porte pas de carrousel → ces ids ne sont dans aucun pool ;
  /// - le blend live (story 9.8) peut renvoyer un jeu d'articles différent du
  ///   slate gelé le matin ;
  /// - tous les articles de l'Essentiel masqués au swipe.
  ///
  /// Les ids **déjà décidés** sont conservés : leur décision est partie au
  /// backend, et le rendu des gardés est déjà gardé par la résolution dans le
  /// pool. L'opération est strictement décroissante ⇒ l'appelant peut la
  /// rejouer sans risque de boucle. Slate vidé ⇒ [hasStarted] redevient faux et
  /// [startIfNeeded] re-gèle sur les articles du jour.
  void pruneUnavailable(Set<String> availableIds) {
    if (!state.hasStarted || availableIds.isEmpty) return;
    final kept = [
      for (final id in state.slate)
        if (availableIds.contains(id) || state.decisions.containsKey(id)) id,
    ];
    if (kept.length == state.slate.length) return;
    state = state.copyWith(
      slate: List.unmodifiable(kept),
      // La cible est volontairement conservée : le pool peut être incomplet
      // pendant un cold-boot (le héros arrive avant le carrousel). Quand le
      // pool complet revient, `startIfNeeded` réinjecte jusqu'à cette cible.
    );
    unawaited(_persist());
  }

  void _trackSessionEnd() {
    final startedMs = _sessionStartMs;
    unawaited(_ref.read(analyticsServiceProvider).trackEssentielTriageSession(
          slateSize: state.slate.length,
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
