import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/models/tile_state.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';

/// Repository en mémoire — implémente le contrat sans réseau.
class _FakeGrilleRepository implements GrilleRepository {
  _FakeGrilleRepository(this.today, {this.guessResult, this.throwOnGuess = false});

  GrilleTodayResponse today;
  GrilleGuessResponse? guessResult;

  /// Simule un échec réseau (timeout) sur le POST guess.
  bool throwOnGuess;

  /// `today` servi à partir du 2e `getToday()` — modélise le re-fetch
  /// silencieux du streak, que le serveur sert incrémenté une fois la partie
  /// du jour terminée.
  GrilleTodayResponse? todayOnRefetch;

  /// Simule un échec réseau sur ce même re-fetch (2e appel et suivants).
  bool throwOnRefetch = false;

  int guessCalls = 0;
  int revealCalls = 0;
  int getTodayCalls = 0;

  @override
  Future<GrilleTodayResponse> getToday() async {
    getTodayCalls++;
    if (getTodayCalls > 1) {
      if (throwOnRefetch) throw Exception('network timeout');
      if (todayOnRefetch != null) return todayOnRefetch!;
    }
    return today;
  }

  @override
  Future<GrilleGuessResponse> submitGuess(String mot) async {
    guessCalls++;
    if (throwOnGuess) {
      throw Exception('network timeout');
    }
    return guessResult ?? const GrilleGuessResponse(valide: false, raison: 'longueur');
  }

  @override
  Future<GrilleRevealResponse> revealWord() async {
    revealCalls++;
    return const GrilleRevealResponse(
      statut: 'revealed',
      mot: 'CLIMAT',
      pourquoi: 'parce que',
    );
  }

  @override
  Future<GrilleLeaderboardResponse> getLeaderboard() async =>
      throw UnimplementedError();
}

GrilleTodayResponse _todayInProgress() => const GrilleTodayResponse(
      date: '2026-05-30',
      dateAffichee: 'Vendredi 30 mai',
      dateCourt: 'Ven. 30 mai',
      numero: 'N°143',
      longueur: 6,
      essaisMax: 6,
      premiereLettre: 'C',
      indice: 'indice',
      theme: 'theme',
      statut: 'in_progress',
      essais: [],
      nbEssais: 0,
      streak: 5,
      prochainMotDansSec: 1000,
    );

/// Même journée, mais servie par le serveur avec la série incrémentée (la
/// partie du jour est terminée côté base).
GrilleTodayResponse _todayWithStreak(int streak) =>
    _todayInProgress().copyWith(streak: streak);

const _guessSolved = GrilleGuessResponse(
  valide: true,
  etats: ['place', 'place', 'place', 'place', 'place', 'place'],
  statut: 'solved',
  nbEssais: 1,
  mot: 'CLIMAT',
  pourquoi: 'parce que',
);

Future<ProviderContainer> _container(_FakeGrilleRepository repo) async {
  final c = ProviderContainer(
    overrides: [grilleRepositoryProvider.overrideWithValue(repo)],
  );
  addTearDown(c.dispose);
  // Laisse le build() async résoudre.
  await c.read(grilleProvider.future);
  return c;
}

void main() {
  test('1re lettre offerte : pré-saisie dans le draft au chargement', () async {
    final repo = _FakeGrilleRepository(_todayInProgress());
    final c = await _container(repo);
    expect(c.read(grilleProvider).value!.draft, 'C');
  });

  test('longueur incomplète : refus local, aucun appel réseau, draft préservé',
      () async {
    final repo = _FakeGrilleRepository(_todayInProgress());
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    // 'C' déjà offerte ; l'utilisateur ajoute 'L','I'.
    for (final l in ['L', 'I']) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(repo.guessCalls, 0, reason: 'pas de POST si longueur incomplète');
    expect(s.invalidReason, 'longueur');
    expect(s.invalidNonce, 1);
    expect(s.draft, 'CLI', reason: 'la saisie (1re offerte incluse) est conservée');
    expect(s.today.essais, isEmpty);
  });

  test('valide=false : essai NON consommé, shake, draft préservé', () async {
    final repo = _FakeGrilleRepository(
      _todayInProgress(),
      guessResult: const GrilleGuessResponse(
        valide: false,
        raison: 'hors_dictionnaire',
      ),
    );
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    // 'C' offerte + 'LACER' → 'CLACER'.
    for (final l in 'LACER'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(repo.guessCalls, 1);
    expect(s.invalidReason, 'hors_dictionnaire');
    expect(s.invalidNonce, 1);
    expect(s.draft, 'CLACER', reason: 'essai non consommé → saisie conservée');
    expect(s.today.essais, isEmpty);
    expect(s.submitting, isFalse);
  });

  test('valide=true solved : essai ajouté, draft vidé, justFinished', () async {
    final repo = _FakeGrilleRepository(
      _todayInProgress(),
      guessResult: const GrilleGuessResponse(
        valide: true,
        etats: ['place', 'place', 'place', 'place', 'place', 'place'],
        statut: 'solved',
        nbEssais: 1,
        mot: 'CLIMAT',
        pourquoi: 'parce que',
      ),
    );
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    // 'C' offerte + 'LIMAT' → 'CLIMAT'.
    for (final l in 'LIMAT'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(s.today.essais.length, 1);
    expect(s.today.essais.single.mot, 'CLIMAT');
    expect(s.today.isSolved, isTrue);
    expect(s.today.mot, 'CLIMAT');
    expect(s.draft, isEmpty, reason: 'partie finie → pas de nouvelle ligne');
    expect(s.justFinished, isTrue);
    expect(s.revealRow, 0);

    // Le clavier reflète les états après l'essai.
    final kb = c.read(grilleKeyboardStatesProvider);
    expect(kb['C'], TileState.place);
    expect(kb['M'], TileState.place);

    // consumeJustFinished éteint le flag transitoire.
    notifier.consumeJustFinished();
    expect(c.read(grilleProvider).value!.justFinished, isFalse);
  });

  test('valide=true non finie : nouvelle ligne re-pré-saisit la 1re lettre',
      () async {
    final repo = _FakeGrilleRepository(
      _todayInProgress(),
      guessResult: const GrilleGuessResponse(
        valide: true,
        etats: ['place', 'absent', 'absent', 'absent', 'absent', 'absent'],
        statut: 'in_progress',
        nbEssais: 1,
      ),
    );
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    for (final l in 'LACER'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(s.today.essais.length, 1);
    expect(s.today.isFinished, isFalse);
    expect(s.draft, 'C', reason: 'la ligne suivante repart sur la 1re offerte');
    expect(s.justFinished, isFalse);
  });

  test('reveal : mot exposé, statut revealed, justFinished reste faux',
      () async {
    final repo = _FakeGrilleRepository(_todayInProgress());
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    await notifier.reveal();

    final s = c.read(grilleProvider).value!;
    expect(repo.revealCalls, 1);
    expect(s.today.isRevealed, isTrue);
    expect(s.today.isFinished, isTrue);
    expect(s.today.mot, 'CLIMAT');
    expect(s.today.pourquoi, 'parce que');
    expect(s.justFinished, isFalse, reason: 'révéler n’est pas une victoire');
    expect(s.draft, isEmpty);
  });

  test('échec réseau : networkError posé, submitting reset, pas de rethrow, '
      'self-heal re-fetch', () async {
    final repo = _FakeGrilleRepository(_todayInProgress(), throwOnGuess: true);
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);
    final getTodayBefore = repo.getTodayCalls;

    for (final l in 'LIMAT'.split('')) {
      notifier.addLetter(l);
    }
    // Ne doit PAS rejeter (le rethrow était la source du freeze).
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(repo.guessCalls, 1);
    expect(s.networkError, isTrue, reason: 'erreur réseau ré-essayable');
    expect(s.submitting, isFalse, reason: 'le clavier se réactive');
    expect(s.today.essais, isEmpty, reason: 'aucun essai consommé localement');
    expect(repo.getTodayCalls, getTodayBefore + 1,
        reason: '_reconcileToday re-fetch le today (self-heal)');

    // Une nouvelle frappe efface l'état d'erreur réseau.
    notifier.addLetter('Z');
    expect(c.read(grilleProvider).value!.networkError, isFalse);
  });

  // ----- série (streak) : re-sync après la partie ---------------------------
  // Régression : docs/bugs/bug-grille-streak-fige-apres-partie.md — le streak
  // servi par `getToday()` s'arrête à hier (la journée n'est pas encore jouée)
  // et le POST guess/reveal n'en renvoie pas, d'où un compteur figé sur N-1.

  test('partie terminée : le streak est re-synchronisé depuis le serveur',
      () async {
    final repo = _FakeGrilleRepository(
      _todayInProgress(),
      guessResult: _guessSolved,
    )..todayOnRefetch = _todayWithStreak(6);
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    for (final l in 'LIMAT'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();
    await pumpEventQueue();

    final s = c.read(grilleProvider).value!;
    expect(repo.getTodayCalls, 2, reason: 'un re-fetch après la fin de partie');
    expect(s.today.streak, 6, reason: 'la série intègre la journée jouée');
    // Le re-fetch ne recopie QUE le streak : l'état de la partie est intact.
    expect(s.today.essais.length, 1);
    expect(s.today.isSolved, isTrue);
    expect(s.today.mot, 'CLIMAT');
    expect(s.justFinished, isTrue);
  });

  test('partie en cours : aucun re-fetch de streak', () async {
    final repo = _FakeGrilleRepository(
      _todayInProgress(),
      guessResult: const GrilleGuessResponse(
        valide: true,
        etats: ['place', 'absent', 'absent', 'absent', 'absent', 'absent'],
        statut: 'in_progress',
        nbEssais: 1,
      ),
    )..todayOnRefetch = _todayWithStreak(6);
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    for (final l in 'LACER'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();
    await pumpEventQueue();

    expect(repo.getTodayCalls, 1);
    expect(c.read(grilleProvider).value!.today.streak, 5);
  });

  test('reveal : le streak est re-synchronisé (journée jouée)', () async {
    final repo = _FakeGrilleRepository(_todayInProgress())
      ..todayOnRefetch = _todayWithStreak(6);
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    await notifier.reveal();
    await pumpEventQueue();

    final s = c.read(grilleProvider).value!;
    expect(repo.getTodayCalls, 2);
    expect(s.today.streak, 6);
    expect(s.today.isRevealed, isTrue, reason: 'statut révélé conservé');
    expect(s.today.mot, 'CLIMAT');
  });

  test('re-fetch du streak en échec : la partie jouée reste intacte', () async {
    final repo = _FakeGrilleRepository(
      _todayInProgress(),
      guessResult: _guessSolved,
    )..throwOnRefetch = true;
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    for (final l in 'LIMAT'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();
    await pumpEventQueue();

    final s = c.read(grilleProvider).value!;
    expect(s.today.streak, 5, reason: 'best-effort : ancienne valeur conservée');
    expect(s.today.isSolved, isTrue);
    expect(s.today.essais.length, 1);
  });

  test('addLetter borné à longueur ; removeLetter ne supprime jamais la 1re',
      () async {
    final repo = _FakeGrilleRepository(_todayInProgress());
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    // 'C' offerte + frappe au-delà de la longueur → borné à 6.
    for (final l in 'LIMATXYZ'.split('')) {
      notifier.addLetter(l);
    }
    expect(c.read(grilleProvider).value!.draft, 'CLIMAT'); // borné à 6

    notifier.removeLetter();
    expect(c.read(grilleProvider).value!.draft, 'CLIMA');

    // On vide au-delà du plancher : la 1re lettre offerte reste verrouillée.
    for (var i = 0; i < 10; i++) {
      notifier.removeLetter();
    }
    expect(c.read(grilleProvider).value!.draft, 'C');
  });
}
