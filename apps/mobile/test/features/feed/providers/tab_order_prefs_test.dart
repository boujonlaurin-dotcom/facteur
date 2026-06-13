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
}
