import 'package:facteur/features/feed/providers/tab_order_prefs_provider.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('applyOrder', () {
    String keyOf(String s) => s;

    test('empty order → items unchanged', () {
      final items = ['a', 'b', 'c'];
      expect(applyOrder(items, const [], keyOf), ['a', 'b', 'c']);
    });

    test('reorders items according to order', () {
      final items = ['a', 'b', 'c'];
      expect(
        applyOrder(items, const ['c', 'a', 'b'], keyOf),
        ['c', 'a', 'b'],
      );
    });

    test('items absent from order keep their relative position, at the end',
        () {
      final items = ['a', 'b', 'c', 'd'];
      // Seuls c et a sont ordonnés → ils passent devant ; b et d (absents)
      // suivent dans leur ordre d'origine.
      expect(
        applyOrder(items, const ['c', 'a'], keyOf),
        ['c', 'a', 'b', 'd'],
      );
    });

    test('order keys absent from items are ignored', () {
      final items = ['a', 'b'];
      expect(
        applyOrder(items, const ['ghost', 'b', 'a'], keyOf),
        ['b', 'a'],
      );
    });

    test('key builders produce the expected prefixes', () {
      expect(tabOrderTopicKey('t1'), 'topic:t1');
      expect(tabOrderSourceKey('s1'), 'source:s1');
    });
  });

  group('mergeVisibleReorder', () {
    test('prevOrder vide → renvoie visibleOrder tel quel', () {
      expect(mergeVisibleReorder(const [], const ['a', 'b']), ['a', 'b']);
    });

    test('permute uniquement les clés visibles, préserve les non rendues', () {
      // s2 n'est pas rendu (catalogue en cours) → doit rester dans l'ordre.
      // L'utilisateur a permuté tech avant s1 parmi les tuiles visibles.
      expect(
        mergeVisibleReorder(
          const ['source:s1', 'source:s2', 'theme:tech'],
          const ['theme:tech', 'source:s1'],
        ),
        // s2 préservé à sa position absolue (slot du milieu) ; l'ordre relatif
        // des visibles == visibleOrder.
        ['theme:tech', 'source:s2', 'source:s1'],
      );
    });

    test('une clé non rendue ne peut jamais être perdue', () {
      final merged = mergeVisibleReorder(
        const ['source:s1', 'source:s2'],
        const ['source:s1'], // s2 non matérialisé
      );
      expect(merged, contains('source:s2'));
    });

    test('clés visibles nouvelles (absentes de prevOrder) → en queue', () {
      expect(
        mergeVisibleReorder(
          const ['source:s1'],
          const ['source:s1', 'theme:tech', 'essentiel'],
        ),
        ['source:s1', 'theme:tech', 'essentiel'],
      );
    });

    test('préserve une clé masquée à sa place lors d\'un réordre', () {
      // `bonnes` masquée (non rendue) entre deux blocs réordonnés.
      expect(
        mergeVisibleReorder(
          const ['essentiel', 'bonnes', 'source:s1'],
          const ['source:s1', 'essentiel'],
        ),
        ['source:s1', 'bonnes', 'essentiel'],
      );
    });

    test('aucune clé visible n\'est perdue ni dupliquée', () {
      final merged = mergeVisibleReorder(
        const ['a', 'b', 'c', 'd'],
        const ['c', 'a'], // b, d non rendus
      );
      expect(merged.toSet(), {'a', 'b', 'c', 'd'});
      expect(merged.length, 4);
      // Ordre relatif des visibles respecté : c avant a.
      expect(merged.indexOf('c'), lessThan(merged.indexOf('a')));
    });
  });
}
