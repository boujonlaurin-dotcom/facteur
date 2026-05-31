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
  test('longueur incomplète : refus local, aucun appel réseau, draft préservé',
      () async {
    final repo = _FakeGrilleRepository(_todayInProgress());
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    for (final l in ['C', 'L', 'I']) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(repo.guessCalls, 0, reason: 'pas de POST si longueur incomplète');
    expect(s.invalidReason, 'longueur');
    expect(s.invalidNonce, 1);
    expect(s.draft, 'CLI', reason: 'la saisie est conservée');
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

    for (final l in 'PLACER'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(repo.guessCalls, 1);
    expect(s.invalidReason, 'hors_dictionnaire');
    expect(s.invalidNonce, 1);
    expect(s.draft, 'PLACER', reason: 'essai non consommé → saisie conservée');
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

    for (final l in 'CLIMAT'.split('')) {
      notifier.addLetter(l);
    }
    await notifier.submitGuess();

    final s = c.read(grilleProvider).value!;
    expect(s.today.essais.length, 1);
    expect(s.today.essais.single.mot, 'CLIMAT');
    expect(s.today.isSolved, isTrue);
    expect(s.today.mot, 'CLIMAT');
    expect(s.draft, isEmpty);
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

  test('addLetter borné à longueur ; removeLetter retire la dernière', () async {
    final repo = _FakeGrilleRepository(_todayInProgress());
    final c = await _container(repo);
    final notifier = c.read(grilleProvider.notifier);

    for (final l in 'CLIMATIQUE'.split('')) {
      notifier.addLetter(l);
    }
    expect(c.read(grilleProvider).value!.draft, 'CLIMAT'); // borné à 6

    notifier.removeLetter();
    expect(c.read(grilleProvider).value!.draft, 'CLIMA');
  });
}
