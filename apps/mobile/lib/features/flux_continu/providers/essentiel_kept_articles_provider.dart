import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/flux_continu_models.dart';
import '../services/tournee_progress_service.dart';

/// Archive du jour des articles **gardés** — le support du contrat « un gardé
/// est gardé pour toute la journée » (bug-essentiel-gardes-disparaissent).
///
/// Le tri ne persiste que des `contentId` (`essentiel_triage_provider.dart` :
/// `slate` + `decisions`). Le rendu, lui, résolvait ces ids contre le pool
/// *courant* de la carte et sautait silencieusement ce qu'il n'y trouvait pas.
/// Or ce pool n'est pas stable sur la journée : « L'Essentiel vivant » (story
/// 9.8) **évince les articles lus** de `GET /api/essentiel` passée une grâce de
/// 30 min, et les items du carrousel ne sont jamais persistés. Résultat : les
/// gardés que l'utilisateur avait lus — ceux auxquels il tenait le plus —
/// disparaissaient de sa liste au redémarrage, puis réapparaissaient à leur
/// place d'origine dès que le blend live les re-servait.
///
/// D'où cette archive : la décision voyage désormais **avec son objet**. Même
/// patron que [essentielExtraArticlesProvider] — on persiste le payload, pas
/// l'id — mais alimentée par le pool plutôt que par le réseau.
///
/// Clé jour ([TourneeProgressService.dayKey], bascule 07h30 Paris), purgée
/// comme les autres blobs jour du tri : ces articles n'ont de sens que pour le
/// slate du jour.
const String kEssentielKeptPrefsKeyPrefix = 'essentiel_kept_v1_';

String essentielKeptPrefsKey(String dayKey) =>
    '$kEssentielKeptPrefsKeyPrefix$dayKey';

@immutable
class EssentielKeptArticlesState {
  /// Articles gardés indexés par `contentId`. L'**ordre d'affichage** ne vient
  /// jamais d'ici : il reste celui du slate gelé (`triage.keptContentIds`).
  final Map<String, EssentielArticle> byId;

  /// `true` une fois SharedPreferences relu. Tant que c'est faux, [sync]
  /// n'élague rien : le premier build d'un cold-boot effacerait sinon ce qui a
  /// été archivé la veille au soir.
  final bool hydrated;

  const EssentielKeptArticlesState({
    this.byId = const {},
    this.hydrated = false,
  });
}

class EssentielKeptArticlesNotifier
    extends StateNotifier<EssentielKeptArticlesState> {
  EssentielKeptArticlesNotifier({
    DateTime? now,
    @visibleForTesting EssentielKeptArticlesState? initialState,
  })  : _dayKey = TourneeProgressService.dayKey(now ?? DateTime.now()),
        super(const EssentielKeptArticlesState()) {
    if (initialState != null) {
      state = initialState;
      return;
    }
    unawaited(_hydrate());
  }

  final String _dayKey;

  Future<void> _hydrate() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await TourneeProgressService.purgeDatedPrefsKeys(
        prefs,
        prefix: kEssentielKeptPrefsKeyPrefix,
        keep: essentielKeptPrefsKey(_dayKey),
      );
      // Le notifier peut être disposé pendant les deux `await` ci-dessus
      // (même motif que `EssentielExtraArticlesNotifier`).
      if (!mounted) return;
      final raw = prefs.getString(essentielKeptPrefsKey(_dayKey));
      final archived = <String, EssentielArticle>{};
      final decoded = raw == null ? null : jsonDecode(raw);
      if (decoded is List) {
        for (final item in decoded) {
          if (item is! Map) continue;
          final article =
              EssentielArticle.fromJson(item.cast<String, dynamic>());
          if (article.contentId.isEmpty) continue;
          archived[article.contentId] = article;
        }
      }
      _publishHydrated(archived);
    } catch (e) {
      debugPrint('EssentielKeptArticles: hydrate failed: $e');
      if (!mounted) return;
      _publishHydrated(const {});
    }
  }

  /// Fusionne l'archive relue avec ce qui a été gardé **pendant** la relecture,
  /// puis réécrit le disque si la fusion a apporté quelque chose.
  ///
  /// [sync] ne persiste pas tant que l'hydratation n'a pas eu lieu : sa relecture
  /// est asynchrone, et une écriture partie avant elle écraserait l'archive de
  /// la veille au soir par le seul gardé de la frame courante — le bug qu'on
  /// corrige, reproduit à l'intérieur du correctif.
  void _publishHydrated(Map<String, EssentielArticle> archived) {
    // Ce qui a été archivé pendant la relecture gagne : c'est le payload du
    // pool courant, donc le plus frais.
    final pending = state.byId;
    final merged = {...archived, ...pending};
    state = EssentielKeptArticlesState(
      byId: Map.unmodifiable(merged),
      hydrated: true,
    );
    if (pending.isNotEmpty) unawaited(_persist(merged));
  }

  Future<void> _persist(Map<String, EssentielArticle> byId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        essentielKeptPrefsKey(_dayKey),
        jsonEncode([for (final a in byId.values) a.toJson()]),
      );
    } catch (e) {
      debugPrint('EssentielKeptArticles: persist failed: $e');
    }
  }

  /// Aligne l'archive sur l'état du tri.
  ///
  /// - [resolved] = les gardés que le pool de la carte sait **encore** résoudre.
  ///   Ils sont (ré)archivés : un article ne peut être gardé que depuis le haut
  ///   de pile, donc la capture est garantie au moment du geste, puis
  ///   rafraîchie tant que le backend le sert encore (état de lecture, saved,
  ///   couverture à jour).
  /// - [keptIds] = **tous** les gardés du jour selon le tri. Tout ce qui n'y est
  ///   pas sort de l'archive : « Refaire ? » ([EssentielTriageNotifier.restart])
  ///   et un re-tri en `pass` nettoient donc derrière eux, et l'archive ne peut
  ///   pas grossir au-delà du nombre de gardés du jour.
  ///
  /// Idempotente et sans écriture inutile : un `sync` qui ne change rien ne
  /// touche ni l'état ni SharedPreferences — elle est appelée à chaque build de
  /// la carte.
  void sync({
    required Iterable<EssentielArticle> resolved,
    required Set<String> keptIds,
  }) {
    // Avant hydratation on peut **ajouter** (ne rien perdre du geste en cours)
    // mais jamais élaguer : l'archive relue n'est pas encore là pour se
    // défendre.
    final canPrune = state.hydrated;
    final next = <String, EssentielArticle>{};
    var changed = false;

    for (final entry in state.byId.entries) {
      if (canPrune && !keptIds.contains(entry.key)) {
        changed = true;
        continue;
      }
      next[entry.key] = entry.value;
    }
    for (final article in resolved) {
      final id = article.contentId;
      if (id.isEmpty || !keptIds.contains(id)) continue;
      final previous = next[id];
      if (previous != null && _sameSnapshot(previous, article)) continue;
      next[id] = article;
      changed = true;
    }
    if (!changed) return;

    state = EssentielKeptArticlesState(
      byId: Map.unmodifiable(next),
      hydrated: state.hydrated,
    );
    // Avant hydratation, on ne touche pas au disque : c'est [_publishHydrated]
    // qui écrira, une fois la fusion faite (cf. sa doc).
    if (state.hydrated) unawaited(_persist(next));
  }

  /// Deux payloads valent-ils la même archive ? Compare les champs qui bougent
  /// au fil de la journée (lecture, sauvegarde, couverture) plutôt que
  /// l'identité d'instance : la carte réalloue ses articles à chaque réponse
  /// réseau, et réécrire SharedPreferences à chaque build serait absurde.
  static bool _sameSnapshot(EssentielArticle a, EssentielArticle b) =>
      a.isRead == b.isRead &&
      a.isSaved == b.isSaved &&
      a.isLiked == b.isLiked &&
      a.completedAt == b.completedAt &&
      a.timeSpentSeconds == b.timeSpentSeconds &&
      a.perspectiveCount == b.perspectiveCount &&
      a.sourceCount == b.sourceCount &&
      a.title == b.title &&
      a.thumbnailUrl == b.thumbnailUrl;
}

final essentielKeptArticlesProvider = StateNotifierProvider<
    EssentielKeptArticlesNotifier, EssentielKeptArticlesState>(
  (ref) => EssentielKeptArticlesNotifier(),
);
