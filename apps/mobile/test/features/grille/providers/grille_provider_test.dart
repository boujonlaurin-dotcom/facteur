import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/models/tile_state.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';

/// Repository en mémoire — implémente le contrat sans réseau.
class _FakeGrilleRepository implements GrilleRepository {
  _FakeGrilleRepository(this.today, {this.guessResult});

  GrilleTodayResponse today;
  GrilleGuessResponse? guessResult;
  int guessCalls = 0;

  @override
  Future<GrilleTodayResponse> getToday() async => today;

  @override
  Future<GrilleGuessResponse> submitGuess(String mot) async {
    guessCalls++;
    return guessResult ?? const GrilleGuessResponse(valide: false, raison: 'longueur');
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
