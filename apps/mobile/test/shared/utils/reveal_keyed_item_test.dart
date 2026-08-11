import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/shared/utils/reveal_keyed_item.dart';

void main() {
  const viewport = Size(390, 844);
  const itemHeight = 200.0;
  const itemCount = 60;

  late ScrollController controller;
  late Map<int, GlobalKey> keys;
  late Set<int> built;

  setUp(() {
    controller = ScrollController();
    keys = <int, GlobalKey>{};
    built = <int>{};
  });

  tearDown(() => controller.dispose());

  /// Liste **paresseuse** : chaque élément n'obtient sa clé qu'au moment où le
  /// sliver le construit, exactement comme les cartes du feed.
  Future<void> pumpList(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CustomScrollView(
            controller: controller,
            slivers: [
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, index) {
                    built.add(index);
                    return KeyedSubtree(
                      key: keys.putIfAbsent(index, GlobalKey.new),
                      child: SizedBox(
                        height: itemHeight,
                        child: Text('item-$index'),
                      ),
                    );
                  },
                  childCount: itemCount,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }


  /// `revealKeyedItem` attend des frames entre deux sauts ; dans le binding de
  /// test, personne ne les produit tant qu'on ne pompe pas. On laisse donc le
  /// futur courir pendant que `pumpAndSettle` fait tourner l'horloge.
  Future<void> reveal(WidgetTester tester, Future<void> running) async {
    await tester.pumpAndSettle();
    await running;
    await tester.pumpAndSettle();
  }

  group('revealKeyedItem', () {
    testWidgets('amène en haut une carte déjà construite', (tester) async {
      await pumpList(tester);

      await reveal(tester, revealKeyedItem(
        controller: controller,
        target: () => keys[3],
      ));

      expect(tester.getTopLeft(find.text('item-3')).dy, closeTo(17, 20));
    });

    testWidgets(
      'atteint une carte hors du cacheExtent — le cas du retour de deck',
      (tester) async {
        await pumpList(tester);
        // Prérequis du test : la cible n'existe pas encore, donc un
        // `ensureVisible` seul n'aurait rien à quoi s'accrocher.
        expect(built.contains(40), isFalse);
        expect(keys[40], isNull);

        await reveal(tester, revealKeyedItem(
          controller: controller,
          target: () => keys[40],
        ));

        expect(find.text('item-40'), findsOneWidget);
        expect(tester.getTopLeft(find.text('item-40')).dy, closeTo(17, 20));
      },
    );

    testWidgets('remonte vers une carte située au-dessus', (tester) async {
      await pumpList(tester);
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pumpAndSettle();

      await reveal(tester, revealKeyedItem(
        controller: controller,
        target: () => keys[55],
      ));

      expect(find.text('item-55'), findsOneWidget);
    });

    testWidgets('cible absente : la liste ne part pas en boucle', (
      tester,
    ) async {
      await pumpList(tester);

      await reveal(tester, revealKeyedItem(
        controller: controller,
        target: () => null,
        maxHops: 3,
      ));

      // Elle abandonne après ses sauts au lieu de dérouler tout le feed :
      // quelques écrans parcourus, pas la liste entière, et aucune exception.
      final position = controller.position;
      expect(position.pixels, greaterThan(0));
      expect(position.pixels, lessThan(position.maxScrollExtent));
      expect(tester.takeException(), isNull);
    });

    testWidgets('sans client attaché : no-op', (tester) async {
      final orphan = ScrollController();
      addTearDown(orphan.dispose);
      await pumpList(tester);

      await revealKeyedItem(controller: orphan, target: () => keys[3]);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
