import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../models/grille_models.dart';
import '../models/tile_state.dart';
import '../repositories/grille_repository.dart';

/// État composite de la partie en cours côté UI.
///
/// [today] est la source de vérité serveur (essais joués, statut, mot/pourquoi
/// une fois finie). [draft] est la ligne en cours de saisie (client-only).
/// [justFinished] est un flag **transitoire** posé par [GrilleNotifier.submitGuess]
/// quand la partie vient de se terminer : il aiguille l'écran vers le Résultat
/// (vs Déjà-joué au cold-load) et est consommé une fois lu.
@immutable
class GrilleState {
  const GrilleState({
    required this.today,
    this.draft = '',
    this.justFinished = false,
    this.submitting = false,
    this.invalidNonce = 0,
    this.invalidReason,
    this.revealRow = -1,
  });

  final GrilleTodayResponse today;

  /// Ligne en cours de saisie, en MAJUSCULES (longueur ≤ `today.longueur`).
  final String draft;

  /// Vrai uniquement pour la transition « la partie vient de finir ».
  final bool justFinished;

  /// Un POST `guess` est en vol.
  final bool submitting;

  /// Incrémenté à chaque essai **refusé** → déclenche le shake de la ligne.
  final int invalidNonce;

  /// Raison du dernier refus (`longueur` | `hors_dictionnaire`) ou `null`.
  final String? invalidReason;

  /// Index de la ligne fraîchement révélée (flip), `-1` si aucune.
  final int revealRow;

  GrilleState copyWith({
    GrilleTodayResponse? today,
    String? draft,
    bool? justFinished,
    bool? submitting,
    int? invalidNonce,
    Object? invalidReason = _sentinel,
    int? revealRow,
  }) {
    return GrilleState(
      today: today ?? this.today,
      draft: draft ?? this.draft,
      justFinished: justFinished ?? this.justFinished,
      submitting: submitting ?? this.submitting,
      invalidNonce: invalidNonce ?? this.invalidNonce,
      invalidReason: invalidReason == _sentinel
          ? this.invalidReason
          : invalidReason as String?,
      revealRow: revealRow ?? this.revealRow,
    );
  }

  static const Object _sentinel = Object();
}

/// Repository provider.
final grilleRepositoryProvider = Provider<GrilleRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return GrilleRepository(apiClient);
});

/// Provider principal : charge `today` puis pilote saisie + essais.
final grilleProvider =
    AsyncNotifierProvider<GrilleNotifier, GrilleState>(GrilleNotifier.new);

class GrilleNotifier extends AsyncNotifier<GrilleState> {
  GrilleRepository get _repo => ref.read(grilleRepositoryProvider);

  @override
  Future<GrilleState> build() async {
    final today = await _repo.getToday();
    return GrilleState(today: today, draft: _initialDraft(today));
  }

  GrilleState? get _current => state.value;

  /// Draft initial d'une ligne neuve : la **1re lettre offerte est pré-saisie
  /// et verrouillée** (l'utilisateur ne tape que les lettres suivantes). Vide
  /// si la partie est finie (aucune ligne en cours).
  static String _initialDraft(GrilleTodayResponse today) =>
      today.isFinished ? '' : today.premiereLettre.toUpperCase();

  /// Ajoute une lettre à la ligne en cours (no-op si partie finie / pleine).
  void addLetter(String letter) {
    final s = _current;
    if (s == null || s.today.isFinished || s.submitting) return;
    if (s.draft.length >= s.today.longueur) return;
    final clean = letter.toUpperCase();
    if (clean.length != 1) return;
    // Une nouvelle frappe efface l'éventuel état d'erreur précédent.
    state = AsyncData(s.copyWith(draft: s.draft + clean, invalidReason: null));
  }

  /// Efface la dernière lettre saisie — **sans jamais effacer la 1re lettre
  /// offerte** (verrouillée).
  void removeLetter() {
    final s = _current;
    if (s == null || s.submitting) return;
    final lockedLen = s.today.premiereLettre.length; // 1re lettre verrouillée
    if (s.draft.length <= lockedLen) return;
    state = AsyncData(
      s.copyWith(
        draft: s.draft.substring(0, s.draft.length - 1),
        invalidReason: null,
      ),
    );
  }

  /// Soumet la ligne en cours.
  ///
  /// - longueur incomplète → refus local (shake), aucun appel réseau.
  /// - `valide == false` → refus serveur (shake), **essai non consommé**.
  /// - `valide == true` → essai ajouté à `today`, draft vidé, flip de la
  ///   nouvelle ligne, `justFinished` posé si la partie se termine.
  Future<void> submitGuess() async {
    final s = _current;
    if (s == null || s.today.isFinished || s.submitting) return;

    if (s.draft.length != s.today.longueur) {
      state = AsyncData(
        s.copyWith(
          invalidReason: 'longueur',
          invalidNonce: s.invalidNonce + 1,
        ),
      );
      return;
    }

    state = AsyncData(s.copyWith(submitting: true));
    final mot = s.draft;
    try {
      final res = await _repo.submitGuess(mot);
      final after = _current ?? s;

      if (!res.valide) {
        // Essai refusé : on ne consomme rien, on signale le shake.
        state = AsyncData(
          after.copyWith(
            submitting: false,
            invalidReason: res.raison ?? 'hors_dictionnaire',
            invalidNonce: after.invalidNonce + 1,
          ),
        );
        return;
      }

      final newEssai = GrilleEssai(mot: mot, etats: res.etats ?? const []);
      final essais = [...after.today.essais, newEssai];
      final updatedToday = after.today.copyWith(
        essais: essais,
        statut: res.statut ?? after.today.statut,
        nbEssais: res.nbEssais ?? essais.length,
        mot: res.mot ?? after.today.mot,
        pourquoi: res.pourquoi ?? after.today.pourquoi,
      );

      state = AsyncData(
        after.copyWith(
          today: updatedToday,
          // Nouvelle ligne : re-pré-saisir la 1re lettre offerte (vide si la
          // partie vient de se terminer).
          draft: _initialDraft(updatedToday),
          submitting: false,
          invalidReason: null,
          revealRow: essais.length - 1,
          justFinished: res.isFinished,
        ),
      );
    } on GrilleAlreadyFinishedException {
      // Le serveur considère la partie finie : on resynchronise.
      await refresh();
    } catch (e) {
      final after = _current ?? s;
      state = AsyncData(after.copyWith(submitting: false));
      rethrow;
    }
  }

  /// Consomme le flag transitoire `justFinished` (après aiguillage écran).
  void consumeJustFinished() {
    final s = _current;
    if (s == null || !s.justFinished) return;
    state = AsyncData(s.copyWith(justFinished: false));
  }

  /// Recharge `today` depuis le serveur.
  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final today = await _repo.getToday();
      return GrilleState(today: today);
    });
  }
}

/// État coloré du clavier, déduit des essais joués (pli `place>present>absent`).
final grilleKeyboardStatesProvider = Provider<Map<String, TileState>>((ref) {
  final async = ref.watch(grilleProvider);
  // `.valueOrNull` (et non `.value`) : sur un état d'erreur `.value` re-lève
  // l'exception (cf. docs/bugs/bug-grille-du-jour-crash.md). Chemin latent —
  // ce provider n'est lu que dans la branche `data` de l'écran Grille — mais
  // fermé par cohérence pour éviter tout futur crash en erreur/loading.
  final today = async.valueOrNull?.today;
  if (today == null) return const {};
  return computeKeyboardStates(
    today.essais.map((e) => (mot: e.mot, etats: e.etats)),
  );
});
