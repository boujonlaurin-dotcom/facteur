import 'package:flutter/foundation.dart';

import 'letter.dart';
import 'letter_progress.dart';

/// Échelle des grades de facteur, dérivée 100 % côté client du nombre de
/// lettres complétées. Extensible quand le catalogue gagnera des lettres (PR2).
const facteurLadder = [
  (threshold: 0, title: 'Facteur Stagiaire'),
  (threshold: 1, title: 'Facteur Alternant'),
  (threshold: 2, title: 'Facteur Junior'),
  (threshold: 3, title: 'Facteur Confirmé'),
  (threshold: 4, title: 'Facteur N+1'),
  (threshold: 5, title: 'Head of Facteur France'),
];

@immutable
class FacteurGrade {
  final int level;
  final String title;
  final int completedLetters;

  /// Nombre de lettres complétées requis pour le niveau suivant,
  /// null au dernier grade.
  final int? nextLevelAt;

  /// Progression globale : (lettres complétées + progress de la lettre
  /// active) / lettres avec actions.
  final double globalProgress;

  const FacteurGrade({
    required this.level,
    required this.title,
    required this.completedLetters,
    required this.nextLevelAt,
    required this.globalProgress,
  });

  factory FacteurGrade.fromLetters(List<Letter> letters) {
    // letter_0 (bienvenue) est archivée d'office avec actions: [] — ne compter
    // que les lettres demandant de vraies actions, sinon tout nouvel
    // utilisateur démarre niveau 2.
    final withActions =
        letters.where((l) => l.actions.isNotEmpty).toList(growable: false);
    final completed = withActions
        .where((l) => l.status == LetterStatus.archived)
        .length;

    var index = 0;
    for (var i = 0; i < facteurLadder.length; i++) {
      if (completed >= facteurLadder[i].threshold) index = i;
    }
    final nextLevelAt =
        index < facteurLadder.length - 1 ? facteurLadder[index + 1].threshold : null;

    double global = 0;
    if (withActions.isNotEmpty) {
      var sum = completed.toDouble();
      for (final l in withActions) {
        if (l.status == LetterStatus.active) {
          sum += l.progress.clamp(0.0, 1.0);
        }
      }
      global = (sum / withActions.length).clamp(0.0, 1.0);
    }

    return FacteurGrade(
      level: index + 1,
      title: facteurLadder[index].title,
      completedLetters: completed,
      nextLevelAt: nextLevelAt,
      globalProgress: global,
    );
  }
}

extension LetterProgressGrade on LetterProgressState {
  FacteurGrade get grade => FacteurGrade.fromLetters(letters);
}
