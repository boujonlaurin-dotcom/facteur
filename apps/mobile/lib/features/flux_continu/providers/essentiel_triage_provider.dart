import 'dart:async';
import 'dart:convert';

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
  button('button');

  const TriageVia(this.wire);

  final String wire;
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
      via: json['decided_via'] == TriageVia.button.wire
          ? TriageVia.button
          : TriageVia.swipe,
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

  /// `true` une fois l'état restauré depuis SharedPreferences — évite de rendre
  /// la pile puis de la faire disparaître au cold-boot.
  final bool hydrated;

  const EssentielTriageState({
    required this.dayKey,
    this.slate = const [],
    this.decisions = const {},
    this.hydrated = false,
  });

  const EssentielTriageState.empty()
      : dayKey = '',
        slate = const [],
        decisions = const {},
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
  String? get currentContentId =>
      index < slate.length ? slate[index] : null;

  /// Articles gardés, **dans l'ordre du slate**. `later` compte comme gardé :
  /// mettre de côté est un choix positif, pas un rejet.
  List<String> get keptContentIds => [
        for (final id in slate)
          if (decisions[id]?.decision == TriageDecision.keep ||
              decisions[id]?.decision == TriageDecision.later)
            id,
      ];

  int get keptCount => keptContentIds.length;

  int get passedCount => decisions.values
      .where((e) => e.decision == TriageDecision.pass)
      .length;

  int get laterCount => decisions.values
      .where((e) => e.decision == TriageDecision.later)
      .length;

  EssentielTriageState copyWith({
    String? dayKey,
    List<String>? slate,
    Map<String, TriageEntry>? decisions,
    bool? hydrated,
  }) =>
      EssentielTriageState(
        dayKey: dayKey ?? this.dayKey,
        slate: slate ?? this.slate,
        decisions: decisions ?? this.decisions,
        hydrated: hydrated ?? this.hydrated,
      );

  Map<String, dynamic> toJson() => {
        'day_key': dayKey,
        'slate': slate,
        'decisions': decisions.values.map((e) => e.toJson()).toList(),
      };
}

const String kTriagePrefsKeyPrefix = 'essentiel_triage_v1_';

String triagePrefsKey(String dayKey) => '$kTriagePrefsKeyPrefix$dayKey';

/// Délai de regroupement des envois. Le tri ne doit **jamais** attendre le
/// réseau : les décisions partent en fire-and-forget batché, et un flush forcé
/// couvre la fin de tri et le passage en arrière-plan.
const Duration kTriageFlushDebounce = Duration(seconds: 2);

/// Cap du nombre d'articles réinjectés en une fois par [EssentielTriageNotifier.extendSlate]
/// (« Voir d'autres articles »). Le carrousel du jour en porte jusqu'à 5 : on ne
/// gonfle pas le slate au-delà d'un tri qui reste court.
const int kTriageExtendMax = 5;

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
      state = state.copyWith(slate: slate, decisions: entries, hydrated: true);
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

  /// Fige le slate au **premier geste du jour**, à partir de l'ordre servi par
  /// `GET /api/essentiel`. No-op si le tri a déjà commencé : c'est précisément
  /// ce qui empêche un refetch de rebattre la pile en cours de tri.
  void startIfNeeded(List<String> contentIds) {
    if (state.hasStarted || contentIds.isEmpty) return;
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _shownAt = DateTime.now();
    state = state.copyWith(slate: List.unmodifiable(contentIds));
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

  /// « Voir d'autres articles » — ajoute au slate figé des `contentId`
  /// supplémentaires (items du carrousel du jour non déjà présents), **sans**
  /// toucher aux décisions déjà prises, borné à [kTriageExtendMax]. La pile se
  /// **rouvre** d'elle-même : `index` repointe sur le premier ajout non décidé,
  /// donc `done` redevient faux et `isActive` vrai. Persisté sous la même clé
  /// jour (les ajouts survivent au cold-boot). No-op si le tri n'a pas démarré
  /// ou si rien de neuf n'est à ajouter.
  ///
  /// Le slate reste **figé** au sens de la story (l'ordre existant ne bouge
  /// pas) : on ne fait qu'allonger la queue. Les décisions envoyées ensuite
  /// portent le `slate_size` étendu (via [decide], `state.slate.length`), ce qui
  /// garde `rank ≤ slate_size` côté backend.
  void extendSlate(List<String> extraIds) {
    if (!state.hasStarted) return;
    final existing = state.slate.toSet();
    final additions = <String>[];
    for (final id in extraIds) {
      if (!existing.add(id)) continue; // déjà dans le slate (ou déjà ajouté)
      additions.add(id);
      if (additions.length >= kTriageExtendMax) break;
    }
    if (additions.isEmpty) return;
    _sessionStartMs = DateTime.now().millisecondsSinceEpoch;
    _shownAt = DateTime.now();
    state = state.copyWith(
      slate: List.unmodifiable([...state.slate, ...additions]),
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
