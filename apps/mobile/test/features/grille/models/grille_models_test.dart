import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/grille/models/grille_models.dart';

void main() {
  group('GrilleTodayResponse.fromJson', () {
    test('lit les clés camelCase byte-exact, numero String, mot null', () {
      final json = <String, dynamic>{
        'date': '2026-05-30',
        'dateAffichee': 'Vendredi 30 mai',
        'dateCourt': 'Ven. 30 mai',
        'numero': 'N°143',
        'longueur': 6,
        'essaisMax': 6,
        'premiereLettre': 'C',
        'indice': 'Le mot qui a traversé ta tournée',
        'theme': 'Environnement',
        'statut': 'in_progress',
        'essais': [
          {'mot': 'PLACER', 'etats': ['absent', 'present', 'absent', 'absent', 'absent', 'present']},
        ],
        'nbEssais': 1,
        'mot': null,
        'pourquoi': null,
        'streak': 5,
        'prochainMotDansSec': 47000,
      };
      final r = GrilleTodayResponse.fromJson(json);
      expect(r.numero, 'N°143');
      expect(r.numero, isA<String>());
      expect(r.longueur, 6);
      expect(r.nbEssais, 1);
      expect(r.essais.single.mot, 'PLACER');
      expect(r.essais.single.etats.length, 6);
      expect(r.mot, isNull);
      expect(r.pourquoi, isNull);
      expect(r.prochainMotDansSec, 47000);
      expect(r.isInProgress, isTrue);
      expect(r.isFinished, isFalse);
    });

    test('statut solved expose le mot et les getters', () {
      final r = GrilleTodayResponse.fromJson({
        'date': '2026-05-30',
        'dateAffichee': 'x',
        'dateCourt': 'x',
        'numero': 'N°143',
        'longueur': 6,
        'essaisMax': 6,
        'premiereLettre': 'C',
        'indice': 'x',
        'theme': 'x',
        'statut': 'solved',
        'essais': const <Map<String, dynamic>>[],
        'nbEssais': 3,
        'mot': 'CLIMAT',
        'pourquoi': 'parce que',
        'streak': 5,
        'prochainMotDansSec': 1000,
      });
      expect(r.isSolved, isTrue);
      expect(r.isFinished, isTrue);
      expect(r.mot, 'CLIMAT');
    });
  });

  group('GrilleGuessResponse.fromJson', () {
    test('refus: valide=false, raison seule, pas de crash sur nulls', () {
      final r = GrilleGuessResponse.fromJson({
        'valide': false,
        'raison': 'hors_dictionnaire',
        'etats': null,
        'statut': null,
        'nbEssais': null,
        'mot': null,
        'pourquoi': null,
      });
      expect(r.valide, isFalse);
      expect(r.raison, 'hors_dictionnaire');
      expect(r.etats, isNull);
      expect(r.isFinished, isFalse);
    });

    test('acceptation solved', () {
      final r = GrilleGuessResponse.fromJson({
        'valide': true,
        'raison': null,
        'etats': ['place', 'place', 'place', 'place', 'place', 'place'],
        'statut': 'solved',
        'nbEssais': 3,
        'mot': 'CLIMAT',
        'pourquoi': 'parce que',
      });
      expect(r.valide, isTrue);
      expect(r.isSolved, isTrue);
      expect(r.etats!.length, 6);
    });
  });

  group('Union int | "X" (monScore / score)', () {
    test('leaderboard normalise les scores entiers et "X"', () {
      final r = GrilleLeaderboardResponse.fromJson({
        'percentile': 12,
        'joueurs': 4218,
        'monScore': 3,
        'distribution': [
          {'score': 1, 'pct': 4},
          {'score': 'X', 'pct': 3},
        ],
        'quartier': [
          {'initiales': 'A·M', 'score': 2, 'rang': 1, 'moi': false},
          {'initiales': 'Toi', 'score': 3, 'rang': 2, 'moi': true},
        ],
        'streak': 5,
      });
      expect(r.monScore, '3');
      expect(r.monScoreInt, 3);
      expect(r.distribution[0].score, '1');
      expect(r.distribution[0].scoreInt, 1);
      expect(r.distribution[1].score, 'X');
      expect(r.distribution[1].scoreInt, isNull);
      expect(r.quartier[1].moi, isTrue);
      expect(r.quartier[0].moi, isFalse);
    });

    test('monScore="X" (partie ratée)', () {
      final r = GrilleLeaderboardResponse.fromJson({
        'percentile': 50,
        'joueurs': 100,
        'monScore': 'X',
        'distribution': const <Map<String, dynamic>>[],
        'quartier': const <Map<String, dynamic>>[],
        'streak': 0,
      });
      expect(r.monScore, 'X');
      expect(r.monScoreInt, isNull);
    });
  });
}
