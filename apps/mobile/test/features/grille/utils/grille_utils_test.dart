import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/utils/grille_format.dart';
import 'package:facteur/features/grille/utils/grille_share_text.dart';

void main() {
  group('formatCountdown (NBSP)', () {
    test('heures + minutes : « 13 h 20 » avec NBSP', () {
      final s = formatCountdown(13 * 3600 + 20 * 60);
      expect(s, '13${nbsp}h${nbsp}20');
      expect(s, '13 h 20');
      expect(s.contains(' '), isFalse, reason: 'aucun espace normal');
    });

    test('heures pleines : « 13 h »', () {
      expect(formatCountdown(13 * 3600), '13${nbsp}h');
    });

    test('minutes seules : « 45 min »', () {
      expect(formatCountdown(45 * 60), '45${nbsp}min');
    });

    test('secondes seules + valeurs négatives bornées à 0', () {
      expect(formatCountdown(30), '30${nbsp}s');
      expect(formatCountdown(-5), '0${nbsp}s');
    });
  });

  group('grille emoji sans spoiler', () {
    final today = GrilleTodayResponse.fromJson({
      'date': '2026-05-30',
      'dateAffichee': 'Vendredi 30 mai',
      'dateCourt': 'Ven. 30 mai',
      'numero': 'N°143',
      'longueur': 6,
      'essaisMax': 6,
      'premiereLettre': 'C',
      'indice': 'x',
      'theme': 'x',
      'statut': 'solved',
      'essais': [
        {'mot': 'PLACER', 'etats': ['absent', 'present', 'absent', 'absent', 'absent', 'present']},
        {'mot': 'CLIMAT', 'etats': ['place', 'place', 'place', 'place', 'place', 'place']},
      ],
      'nbEssais': 2,
      'mot': 'CLIMAT',
      'pourquoi': 'parce que',
      'streak': 5,
      'prochainMotDansSec': 1000,
    });

    test('la grille emoji ne contient AUCUNE lettre (anti-spoiler)', () {
      final grid = buildGrilleEmojiGrid(today.essais);
      expect(grid, '⬛🟧⬛⬛⬛🟧\n🟩🟩🟩🟩🟩🟩');
      // Aucune lettre A–Z (le mot ne fuite jamais).
      expect(RegExp(r'[A-Za-z]').hasMatch(grid), isFalse);
    });

    test('texte de partage : en-tête + score N/6 + lien, sans le mot', () {
      final text = buildGrilleShareText(today);
      expect(text, contains('La Grille du jour N°143 · Ven. 30 mai · 2/6'));
      expect(text, contains('🟩🟩🟩🟩🟩🟩'));
      expect(text, contains(buildGrilleShareLink(today)));
      expect(text.contains('CLIMAT'), isFalse, reason: 'le mot ne doit pas fuiter');
    });

    test('score raté = X/6', () {
      final failed = today.copyWith(statut: 'failed', nbEssais: 6);
      expect(grilleShareScore(failed), 'X/6');
    });
  });
}
