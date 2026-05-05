import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/lettres/models/letter.dart';

void main() {
  group('Letter.fromJson backward-compat', () {
    test('parses minimal payload without narrative fields (L0/L1 shape)', () {
      final l = Letter.fromJson({
        'id': 'letter_1',
        'num': '01',
        'title': 'Tes premières sources',
        'message': 'msg',
        'signature': 'Le Facteur',
        'status': 'active',
        'actions': [
          {'id': 'a1', 'label': 'A1', 'help': 'h'},
        ],
        'completed_actions': <String>[],
        'progress': 0.0,
      });

      expect(l.introPalier, isNull);
      expect(l.completionVoeu, isNull);
      expect(l.actions.single.completionPalier, isNull);
    });

    test('parses L2 payload with narrative fields', () {
      final l = Letter.fromJson({
        'id': 'letter_2',
        'num': '02',
        'title': 'Tes premières lectures',
        'message': 'msg',
        'signature': 'Le Facteur',
        'status': 'active',
        'intro_palier': 'Voyons si tu sais en faire bon usage.',
        'completion_voeu': 'Tu as appris à lire avec attention.',
        'actions': [
          {
            'id': 'read_first_essentiel',
            'label': "Lire L'essentiel",
            'help': 'h',
            'completion_palier': 'Premier rendez-vous tenu.',
          },
          {
            'id': 'recommend_first_article',
            'label': 'Recommander',
            'help': 'h',
            'completion_palier': 'Un signal envoyé.',
          },
        ],
        'completed_actions': <String>[],
        'progress': 0.0,
      });

      expect(l.introPalier, 'Voyons si tu sais en faire bon usage.');
      expect(l.completionVoeu, 'Tu as appris à lire avec attention.');
      expect(l.actions[0].completionPalier, 'Premier rendez-vous tenu.');
      expect(l.actions[1].completionPalier, 'Un signal envoyé.');
    });
  });
}
