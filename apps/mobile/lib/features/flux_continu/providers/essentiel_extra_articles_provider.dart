import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flux_continu_models.dart';
import '../repositories/essentiel_repository.dart';
import '../services/tournee_progress_service.dart';

/// Articles Essentiel **rapatriés au réseau** — Story 33.3, puis 33.4 où ils
/// deviennent le carburant de la pile : ce n'est plus seulement le tap sur
/// « Plus d'articles ? » qui les demande, mais le **prefetch automatique** de la
/// carte dès que la pile passe sous [kTriagePrefetchLowWaterMark] articles à
/// trier alors que l'objectif de gardés n'est pas atteint.
///
/// Pourquoi un état persisté et pas un simple `Future` :
///
/// - `syncSlate` pousse leurs `contentId` dans le **slate**, lui-même persisté
///   pour la journée. Au cold-boot suivant, un slate qui référence un article
///   que le pool ne porte plus est élagué par `pruneUnavailable` — la décision
///   de l'utilisateur d'élargir sa pile serait donc annulée par le redémarrage
///   (exactement le piège déjà documenté pour les ids du carrousel) ;
/// - le pool doit être **stable** : réordonner ou re-tirer au boot rebattrait
///   l'ordre d'articles déjà affichés.
///
/// On persiste le **payload brut du backend**, pas l'objet : `EssentielArticle`
/// n'a pas de `toJson`, et le JSON se re-parse à l'identique par
/// `EssentielArticle.fromJson` — même article, mêmes champs, même rang.
///
/// Clé jour ([TourneeProgressService.dayKey], bascule 07h30 Paris), purgée
/// comme celle du tri : ces articles n'ont de sens que pour le slate du jour.
const String kEssentielExtraPrefsKeyPrefix = 'essentiel_extra_v1_';

String essentielExtraPrefsKey(String dayKey) =>
    '$kEssentielExtraPrefsKeyPrefix$dayKey';

/// Nombre d'articles restant à trier en dessous duquel la carte va chercher la
/// suite. 2 : de quoi couvrir la carte du dessus **et** celle du dessous, donc
/// l'utilisateur ne voit jamais la pile se vider sous son doigt.
const int kTriagePrefetchLowWaterMark = 2;

/// Taille d'un lot de prefetch. 5 et non 2 : à 2 restants déclenchant un lot de
/// 5, c'est au pire un appel toutes les 5 décisions.
const int kTriagePrefetchBatch = 5;

/// Plafond de prefetchs **automatiques** par montage de la carte. Garde-fou de
/// dernier recours : un pool sec ne doit jamais devenir une boucle réseau, même
/// si les deux autres gardes ([_inFlight], [kTriageExhaustedCooldown]) sautaient.
const int kTriageMaxAutoFetches = 6;

/// Après un retour à vide, on ne redemande pas avant ce délai. En mémoire et
/// non en SharedPreferences : c'est un état de session, pas une décision de
/// l'utilisateur, et le redémarrage a le droit de retenter.
const Duration kTriageExhaustedCooldown = Duration(minutes: 10);

@immutable
class EssentielExtraArticlesState {
  /// Articles rapatriés, dans leur ordre d'arrivée — jamais retriés.
  final List<EssentielArticle> articles;

  /// `true` une fois SharedPreferences relu. Tant que c'est faux, la carte ne
  /// doit pas conclure que le pool est complet.
  final bool hydrated;

  const EssentielExtraArticlesState({
    this.articles = const [],
    this.hydrated = false,
  });
}

class EssentielExtraArticlesNotifier
    extends StateNotifier<EssentielExtraArticlesState> {
  EssentielExtraArticlesNotifier(
    this._ref, {
    DateTime? now,
    @visibleForTesting EssentielExtraArticlesState? initialState,
  })  : _dayKey = TourneeProgressService.dayKey(now ?? DateTime.now()),
        super(const EssentielExtraArticlesState()) {
    if (initialState != null) {
      state = initialState;
      return;
    }
    unawaited(_hydrate());
  }

  final Ref _ref;
  final String _dayKey;

  /// Payloads bruts déjà connus, dans le même ordre que `state.articles` — ce
  /// qui est réécrit dans SharedPreferences à chaque ajout.
  List<Map<String, dynamic>> _raw = const [];

  /// Un seul appel réseau en vol. C'est la garde anti double-tap : le CTA est
  /// une grande zone tappable, et deux appels concurrents pourraient rapporter
  /// deux fois les mêmes articles (les exclusions du second partiraient avant
  /// que le premier ait publié).
  bool _inFlight = false;

  /// Le pool backend a rendu `[]` : inutile de le redemander avant expiration.
  /// Un tap utilisateur, lui, **force** l'appel — il a le droit d'insister.
  DateTime? _exhaustedUntil;

  /// Prefetchs automatiques déjà consommés. Compteur de vie du notifier (donc
  /// de la session Riverpod), lu par la jauge de fin de tri.
  int _autoFetchCount = 0;

  bool get isLoading => _inFlight;

  int get autoFetchCount => _autoFetchCount;

  /// Le prefetch automatique a-t-il encore le droit de partir ? Lu par la carte
  /// **avant** de poster son callback : une garde côté appelant évite de
  /// reposter une frame pour rien.
  bool canAutoFetch({DateTime? now}) {
    if (_inFlight || _autoFetchCount >= kTriageMaxAutoFetches) return false;
    final until = _exhaustedUntil;
    return until == null || !(now ?? DateTime.now()).isBefore(until);
  }

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await TourneeProgressService.purgeDatedPrefsKeys(
        prefs,
        prefix: kEssentielExtraPrefsKeyPrefix,
        keep: essentielExtraPrefsKey(_dayKey),
      );
      // Le notifier peut être disposé pendant les deux `await` ci-dessus :
      // depuis la 33.4 il est aussi instancié à la volée en fin de tri (pour
      // `autoFetches`), donc sur des durées de vie très courtes. Écrire `state`
      // après coup lèverait un `Bad state`.
      if (!mounted) return;
      final rawString = prefs.getString(essentielExtraPrefsKey(_dayKey));
      if (rawString == null) {
        state = EssentielExtraArticlesState(
          articles: state.articles,
          hydrated: true,
        );
        return;
      }
      final decoded = jsonDecode(rawString);
      final raw = decoded is List
          ? decoded
              .whereType<Map<dynamic, dynamic>>()
              .map((e) => e.cast<String, dynamic>())
              .toList(growable: false)
          : const <Map<String, dynamic>>[];
      _raw = raw;
      state = EssentielExtraArticlesState(
        articles: List.unmodifiable(raw.map(EssentielArticle.fromJson)),
        hydrated: true,
      );
    } catch (e) {
      debugPrint('EssentielExtraArticles: hydrate failed: $e');
      if (!mounted) return;
      state = EssentielExtraArticlesState(
        articles: state.articles,
        hydrated: true,
      );
    }
  }

  Future<void> _persist() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        essentielExtraPrefsKey(_dayKey),
        jsonEncode(_raw),
      );
    } catch (e) {
      debugPrint('EssentielExtraArticles: persist failed: $e');
    }
  }

  /// Demande [limit] articles inédits au backend, en excluant [excludeIds]
  /// (slate ∪ décidés ∪ pool local) **et** ce qui a déjà été rapatrié.
  ///
  /// [excludeIds] doit arriver **ordonné** (slate d'abord, puis pool) : le
  /// backend borne la liste, et ce qui saute doit être ce qui compte le moins.
  ///
  /// [force] = geste utilisateur (tap sur « Plus d'articles ? »). Il ignore le
  /// cooldown d'épuisement et ne consomme pas le quota de prefetchs. Sans lui,
  /// c'est un **prefetch automatique** : soumis aux trois gardes ([_inFlight],
  /// [kTriageExhaustedCooldown], [kTriageMaxAutoFetches]).
  ///
  /// Renvoie les articles réellement ajoutés — vide si le backend n'a rien
  /// d'inédit, si l'appel a échoué, ou s'il a été refusé par une garde.
  /// L'appelant distingue les deux par [isLoading] : il n'affiche « Pas de
  /// nouvel article » que sur un retour à vide, jamais sur un tap absorbé.
  Future<List<EssentielArticle>> fetchMore({
    required List<String> excludeIds,
    int limit = 2,
    bool force = false,
    DateTime? now,
  }) async {
    if (_inFlight) return const [];
    if (!force) {
      if (!canAutoFetch(now: now)) return const [];
      _autoFetchCount++;
    }
    _inFlight = true;
    try {
      final known = {for (final a in state.articles) a.contentId};
      // `LinkedHashSet` par défaut ⇒ l'ordre d'insertion (slate, pool, puis
      // rapatriés) est conservé jusqu'à la requête.
      final exclude = <String>{...excludeIds, ...known};
      final raw = await _ref
          .read(essentielRepositoryProvider)
          .fetchMore(excludeIds: exclude.toList(growable: false), limit: limit);
      // `null` = échec réseau : surtout **pas** un épuisement. Le prochain
      // swipe retentera, sinon une coupure de 3 s figerait la pile 10 min.
      if (raw == null) return const [];
      if (raw.isEmpty) {
        _exhaustedUntil = (now ?? DateTime.now()).add(kTriageExhaustedCooldown);
        return const [];
      }

      final fresh = <EssentielArticle>[];
      final freshRaw = <Map<String, dynamic>>[];
      final excluded = {...exclude};
      for (final json in raw) {
        final article = EssentielArticle.fromJson(json);
        // Double garde : le backend exclut déjà, mais un doublon injecté dans
        // le slate serait irrattrapable (l'article y resterait la journée).
        if (article.contentId.isEmpty || !excluded.add(article.contentId)) {
          continue;
        }
        fresh.add(article);
        freshRaw.add(json);
      }
      // Le backend n'a rendu que des doublons : c'est un pool sec, au même
      // titre qu'une réponse vide.
      if (fresh.isEmpty) {
        _exhaustedUntil = (now ?? DateTime.now()).add(kTriageExhaustedCooldown);
        return const [];
      }
      // Un lot non vide rouvre la vanne : le pool s'est regarni.
      _exhaustedUntil = null;
      if (!mounted) return List.unmodifiable(fresh);

      // **Append seul** : l'ordre de ce qui est déjà affiché ne bouge jamais.
      _raw = List.unmodifiable([..._raw, ...freshRaw]);
      state = EssentielExtraArticlesState(
        articles: List.unmodifiable([...state.articles, ...fresh]),
        hydrated: true,
      );
      unawaited(_persist());
      return List.unmodifiable(fresh);
    } finally {
      _inFlight = false;
    }
  }
}

final essentielExtraArticlesProvider = StateNotifierProvider<
    EssentielExtraArticlesNotifier, EssentielExtraArticlesState>(
  (ref) => EssentielExtraArticlesNotifier(ref),
);
