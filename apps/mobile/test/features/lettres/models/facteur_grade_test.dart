import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/lettres/models/facteur_grade.dart';
import 'package:facteur/features/lettres/models/letter.dart';
import 'package:facteur/features/lettres/models/letter_progress.dart';

Letter _l({
  required String id,
  required LetterStatus status,
  int actionCount = 2,
  double progress = 0.0,
}) =>
    Letter(
      id: id,
      letterNum: '01',
      title: 'Titre',
      message: 'msg',
      signature: 'Le Facteur',
      status: status,
      actions: List.generate(
        actionCount,
        (i) => LetterAction(
          id: 'a$i',
          label: 'Action $i',
          help: '',
          status: LetterActionStatus.todo,
        ),
      ),
      completedActions: const [],
      progress: progress,
      startedAt: null,
      archivedAt: null,
    );

void main() {
  group('FacteurGrade.fromLetters', () {
    test('letter_0 archivée sans actions est ignorée (niveau 1)', () {
      final grade = FacteurGrade.fromLetters([
        _l(id: 'letter_0', status: LetterStatus.archived, actionCount: 0),
        _l(id: 'letter_1', status: LetterStatus.active),
      ]);
      expect(grade.level, 1);
      expect(grade.title, 'Facteur Stagiaire');
      expect(grade.completedLetters, 0);
      expect(grade.nextLevelAt, 1);
    });

    test('1 lettre complétée → niveau 2', () {
      final grade = FacteurGrade.fromLetters([
        _l(id: 'letter_0', status: LetterStatus.archived, actionCount: 0),
        _l(id: 'letter_1', status: LetterStatus.archived),
        _l(id: 'letter_2', status: LetterStatus.active),
      ]);
      expect(grade.level, 2);
      expect(grade.title, 'Facteur Alternant');
      expect(grade.completedLetters, 1);
      expect(grade.nextLevelAt, 2);
    });

    test('2 lettres complétées → niveau 3', () {
      final grade = FacteurGrade.fromLetters([
        _l(id: 'letter_1', status: LetterStatus.archived),
        _l(id: 'letter_2', status: LetterStatus.archived),
      ]);
      expect(grade.level, 3);
      expect(grade.title, 'Facteur Junior');
    });

    test('5 lettres complétées → niveau 6 (sommet)', () {
      final grade = FacteurGrade.fromLetters([
        for (var i = 0; i < 5; i++)
          _l(id: 'letter_$i', status: LetterStatus.archived),
      ]);
      expect(grade.level, 6);
      expect(grade.title, 'Head of Facteur France');
      expect(grade.nextLevelAt, isNull);
    });

    test('clamp sur le dernier grade au-delà de 5 lettres', () {
      final grade = FacteurGrade.fromLetters([
        for (var i = 0; i < 9; i++)
          _l(id: 'letter_$i', status: LetterStatus.archived),
      ]);
      expect(grade.level, 6);
      expect(grade.title, 'Head of Facteur France');
      expect(grade.nextLevelAt, isNull);
    });

    test('globalProgress mêle lettres complétées et progress active', () {
      final grade = FacteurGrade.fromLetters([
        _l(id: 'letter_1', status: LetterStatus.archived),
        _l(id: 'letter_2', status: LetterStatus.active, progress: 0.5),
        _l(id: 'letter_3', status: LetterStatus.upcoming),
        _l(id: 'letter_4', status: LetterStatus.upcoming),
      ]);
      // (1 + 0.5) / 4
      expect(grade.globalProgress, closeTo(0.375, 0.0001));
    });

    test('globalProgress vaut 0 sans lettre avec actions', () {
      final grade = FacteurGrade.fromLetters([
        _l(id: 'letter_0', status: LetterStatus.archived, actionCount: 0),
      ]);
      expect(grade.globalProgress, 0);
    });
  });

  test('extension grade sur LetterProgressState', () {
    final state = LetterProgressState(letters: [
      _l(id: 'letter_1', status: LetterStatus.archived),
    ]);
    expect(state.grade.level, 2);
  });
}
