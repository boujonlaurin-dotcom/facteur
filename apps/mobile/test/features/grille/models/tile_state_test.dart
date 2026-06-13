import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/grille/models/tile_state.dart';

void main() {
  group('TileStateX.fromServer', () {
    test('mappe les trois états serveur', () {
      expect(TileStateX.fromServer('place'), TileState.place);
      expect(TileStateX.fromServer('present'), TileState.present);
      expect(TileStateX.fromServer('absent'), TileState.absent);
    });

    test('dégrade une valeur inconnue en absent (pas de crash)', () {
      expect(TileStateX.fromServer('wat'), TileState.absent);
      expect(TileStateX.fromServer(''), TileState.absent);
    });
  });

  group('shareEmoji', () {
    test('emoji sans spoiler pour les états révélés', () {
      expect(TileState.place.shareEmoji, '🟩');
      expect(TileState.present.shareEmoji, '🟧');
      expect(TileState.absent.shareEmoji, '⬛');
    });

    test('états client-only sans emoji', () {
      expect(TileState.empty.shareEmoji, '');
      expect(TileState.filled.shareEmoji, '');
      expect(TileState.hint.shareEmoji, '');
    });
  });

  group('computeKeyboardStates (rang place > present > absent)', () {
    test('garde le rang le plus fort par lettre', () {
      // C en absent (essai 1) puis place (essai 2) → doit finir place.
      final states = computeKeyboardStates([
        (mot: 'PLACER', etats: ['absent', 'absent', 'absent', 'present', 'absent', 'present']),
        (mot: 'CLIMAT', etats: ['place', 'place', 'absent', 'present', 'absent', 'place']),
      ]);
      expect(states['C'], TileState.place); // present→place gagne
      expect(states['L'], TileState.place);
      expect(states['R'], TileState.present); // present, jamais bien placé
      expect(states['A'], TileState.absent); // absente dans les deux essais
      expect(states['T'], TileState.place);
      expect(states['P'], TileState.absent);
    });

    test('un present ne rétrograde jamais un place déjà acquis', () {
      final states = computeKeyboardStates([
        (mot: 'AA', etats: ['place', 'present']),
      ]);
      expect(states['A'], TileState.place);
    });

    test('minuscules normalisées en majuscules', () {
      final states = computeKeyboardStates([
        (mot: 'climat', etats: ['place', 'absent', 'absent', 'absent', 'absent', 'absent']),
      ]);
      expect(states.containsKey('C'), isTrue);
      expect(states['C'], TileState.place);
    });

    test('aucune lettre pour une liste vide', () {
      expect(computeKeyboardStates([]), isEmpty);
    });
  });
}
