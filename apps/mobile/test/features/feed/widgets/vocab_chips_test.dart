import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show HighlightSpan;
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

Perspective _p(String name, List<HighlightSpan> spans) => Perspective(
      title: 'Titre $name',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: 'center',
      highlightSpans: spans,
    );

HighlightSpan _h(String text, String bias, {double? weight}) =>
    HighlightSpan(start: 0, end: text.length, text: text, bias: bias, weight: weight);

void main() {
  group('deriveVocabChips', () {
    test('un chip par groupe de bias, ordonné gauche → droite', () {
      final chips = deriveVocabChips([
        _p('A', [_h('abat', 'right', weight: 1.0)]),
        _p('B', [_h('revendique', 'left', weight: 1.0)]),
        _p('C', [_h('selon', 'center', weight: 0.5)]),
      ]);
      expect(chips.map((c) => c.bias).toList(), ['left', 'center', 'right']);
      expect(chips.map((c) => c.text).toList(),
          ['revendique', 'selon', 'abat']);
    });

    test('garde le mot de POIDS MAX par bias', () {
      final chips = deriveVocabChips([
        _p('A', [
          _h('faible', 'left', weight: 0.25),
          _h('fort', 'left', weight: 1.0),
          _h('moyen', 'left', weight: 0.5),
        ]),
      ]);
      expect(chips.length, 1);
      expect(chips.single.text, 'fort');
    });

    test('dédupe par mot minuscule (entre biais)', () {
      final chips = deriveVocabChips([
        _p('A', [_h('Cartel', 'left', weight: 1.0)]),
        _p('B', [_h('cartel', 'right', weight: 0.9)]),
      ]);
      // Même mot (casse ignorée) → un seul chip, le premier rencontré (L→R).
      expect(chips.length, 1);
      expect(chips.single.bias, 'left');
    });

    test('ignore les spans vides', () {
      final chips = deriveVocabChips([
        _p('A', [_h('   ', 'left', weight: 1.0)]),
      ]);
      expect(chips, isEmpty);
    });

    test('liste vide → aucun chip', () {
      expect(deriveVocabChips(const []), isEmpty);
    });
  });

  group('biasColorFromString', () {
    final colors = FacteurPalettes.light;

    test('mappe chaque bord politique sur sa couleur', () {
      expect(biasColorFromString('left', colors), colors.biasLeft);
      expect(biasColorFromString('center-left', colors), colors.biasCenterLeft);
      expect(biasColorFromString('center', colors), colors.biasCenter);
      expect(
          biasColorFromString('center-right', colors), colors.biasCenterRight);
      expect(biasColorFromString('right', colors), colors.biasRight);
    });

    test('valeur inconnue → biasUnknown', () {
      expect(biasColorFromString('weird', colors), colors.biasUnknown);
    });
  });
}
