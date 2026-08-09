import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/detail/deck/models/article_deck.dart';
import 'package:facteur/features/detail/deck/widgets/article_deck_view.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';

Content _content(String id) => Content(
      id: id,
      title: 'title-$id',
      url: 'https://x.test/$id',
      contentType: ContentType.article,
      publishedAt: DateTime(2026, 1, 1),
      source: Source(id: 's', name: 'S', type: SourceType.article),
    );

ArticleDeckPayload _deck({
  int count = 3,
  int initialIndex = 0,
  void Function(Content article)? onArticleSettled,
}) {
  return ArticleDeckPayload(
    articles: List.generate(count, (i) => _content('c$i')),
    initialIndex: initialIndex,
    sectionKey: 'theme:tech',
    sectionLabel: 'Tech',
    onArticleSettled: onArticleSettled,
  );
}

void main() {
  const viewport = Size(390, 844);

  /// Slots vus par le builder, dernier état connu par index.
  late Map<int, bool> activeByIndex;
  late List<(int, int)> changes;

  setUp(() {
    activeByIndex = <int, bool>{};
    changes = <(int, int)>[];
  });

  Future<void> pumpDeck(
    WidgetTester tester, {
    ArticleDeckPayload? deck,
  }) async {
    await tester.binding.setSurfaceSize(viewport);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final payload = deck ?? _deck();
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ArticleDeckView(
                      deck: payload,
                      onArticleChanged: (from, to) => changes.add((from, to)),
                      pageBuilder: (context, slot) {
                        activeByIndex[slot.index] = slot.isActive;
                        return ColoredBox(
                          color: Colors.white,
                          child: Center(
                            child: Text(
                              'article-${payload.articles[slot.index].id}',
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
  }

  Future<void> dragBy(WidgetTester tester, double dx) async {
    final gesture = await tester.startGesture(const Offset(195, 400));
    const steps = 12;
    for (var i = 0; i < steps; i++) {
      await gesture.moveBy(Offset(dx / steps, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('ArticleDeckView', () {
    testWidgets('glisser vers la gauche mène à l’article suivant', (
      tester,
    ) async {
      await pumpDeck(tester);
      expect(find.text('article-c0'), findsOneWidget);

      await dragBy(tester, -300);

      expect(find.text('article-c1'), findsOneWidget);
      expect(changes, [(0, 1)]);
    });

    testWidgets('glisser vers la droite mène à l’article précédent', (
      tester,
    ) async {
      await pumpDeck(tester, deck: _deck(initialIndex: 2));
      expect(find.text('article-c2'), findsOneWidget);

      await dragBy(tester, 300);

      expect(find.text('article-c1'), findsOneWidget);
      expect(changes, [(2, 1)]);
    });

    testWidgets('le dernier article ne mène nulle part vers la gauche', (
      tester,
    ) async {
      await pumpDeck(tester, deck: _deck(initialIndex: 2));

      await dragBy(tester, -300);

      expect(find.text('article-c2'), findsOneWidget);
      expect(changes, isEmpty);
    });

    testWidgets(
      'le dernier article : le sur-défilement bute sur le mur de fin',
      (tester) async {
        await pumpDeck(tester, deck: _deck(initialIndex: 2));
        final position = tester
            .state<ScrollableState>(find.byType(Scrollable).first)
            .position;

        // Course longue vers la gauche, maintenue : sans mur, le rebond
        // découvrait presque une demi-largeur d’écran — lu comme une page
        // suivante vide (fond de route noir).
        final gesture = await tester.startGesture(const Offset(195, 400));
        var maxOverscroll = 0.0;
        // Course gagnée par pas de doigt : c'est elle qui doit fondre.
        final gains = <double>[];
        for (var i = 0; i < 12; i++) {
          await gesture.moveBy(const Offset(-40, 0));
          await tester.pump(const Duration(milliseconds: 16));
          final overscroll = position.pixels - position.maxScrollExtent;
          if (overscroll > maxOverscroll) {
            gains.add(overscroll - maxOverscroll);
            maxOverscroll = overscroll;
          }
        }

        expect(maxOverscroll, greaterThan(0), reason: 'la pile doit bouger');
        expect(maxOverscroll, lessThanOrEqualTo(32.5));

        // …et la butée n'est pas sèche : le mur est élastique, donc la course
        // gagnée par 40 px de doigt fond à mesure qu'on s'en approche.
        expect(
          gains.last,
          lessThan(gains.first / 4),
          reason: 'le déplacement doit s’amortir, pas se figer d’un coup',
        );
        expect(gains.last, greaterThan(0), reason: 'jamais tout à fait bloqué');

        await gesture.up();
        await tester.pumpAndSettle();

        // Et la pile revient au repos sur le dernier article.
        expect(position.pixels, moreOrLessEquals(position.maxScrollExtent));
        expect(find.text('article-c2'), findsOneWidget);
        expect(changes, isEmpty);
      },
    );

    testWidgets(
      'le fond du deck est peint — jamais le noir de la route',
      (tester) async {
        await pumpDeck(tester, deck: _deck(initialIndex: 2));

        expect(
          find.descendant(
            of: find.byType(ArticleDeckView),
            matching: find.byWidgetPredicate(
              (w) =>
                  w is ColoredBox &&
                  w.color == FacteurPalettes.light.backgroundPrimary,
            ),
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets(
      'le 1ᵉʳ article : tirer vers la droite referme le deck',
      (tester) async {
        await pumpDeck(tester);

        await dragBy(tester, 320);
        await tester.pumpAndSettle();

        expect(find.text('article-c0'), findsNothing);
        expect(find.text('Ouvrir'), findsOneWidget);
        // Sortir de la section n’est pas un changement d’article.
        expect(changes, isEmpty);
      },
    );

    testWidgets(
      'le 1ᵉʳ article : un tirage court rebondit sans refermer',
      (tester) async {
        await pumpDeck(tester);

        await dragBy(tester, 24);

        expect(find.text('article-c0'), findsOneWidget);
        expect(changes, isEmpty);
      },
    );

    testWidgets(
      'seule la page validée est active — un voisin entrevu ne l’est pas',
      (tester) async {
        await pumpDeck(tester);
        expect(activeByIndex[0], isTrue);

        // Geste interrompu à mi-course : le voisin est construit (il est à
        // l’écran) mais ne doit pas être considéré comme ouvert.
        final gesture = await tester.startGesture(const Offset(195, 400));
        for (var i = 0; i < 6; i++) {
          await gesture.moveBy(const Offset(-20, 0));
          await tester.pump(const Duration(milliseconds: 16));
        }
        await tester.pump();

        expect(activeByIndex[1], isFalse);
        expect(changes, isEmpty);

        await gesture.up();
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'la surface d’origine est notifiée de l’article d’arrivée',
      (tester) async {
        final settled = <String>[];
        await pumpDeck(
          tester,
          deck: _deck(onArticleSettled: (a) => settled.add(a.id)),
        );

        await dragBy(tester, -300);
        await dragBy(tester, -300);

        // C’est ce fil qui permet au feed de se rouvrir sur c2 et non sur c0.
        expect(settled, ['c1', 'c2']);
      },
    );

    testWidgets(
      'un voisin seulement entrevu ne notifie pas d’arrivée',
      (tester) async {
        final settled = <String>[];
        await pumpDeck(
          tester,
          deck: _deck(onArticleSettled: (a) => settled.add(a.id)),
        );

        // Geste annulé : le feed ne doit pas se repositionner sur un article
        // qu’on n’a jamais ouvert.
        await dragBy(tester, -40);

        expect(settled, isEmpty);
      },
    );

    testWidgets('l’état d’une page survit à un aller-retour de geste', (
      tester,
    ) async {
      await pumpDeck(tester);
      final stateBefore = tester.state<State<ArticleDeckView>>(
        find.byType(ArticleDeckView),
      );

      // Course puis retour en arrière : l’enveloppe de transformation change de
      // valeurs mais jamais de forme, la page ne doit pas être réinflatée.
      final gesture = await tester.startGesture(const Offset(195, 400));
      await gesture.moveBy(const Offset(-80, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.moveBy(const Offset(80, 0));
      await tester.pump(const Duration(milliseconds: 16));
      await gesture.up();
      await tester.pumpAndSettle();

      expect(
        tester.state<State<ArticleDeckView>>(find.byType(ArticleDeckView)),
        same(stateBefore),
      );
      expect(find.text('article-c0'), findsOneWidget);
      expect(changes, isEmpty);
    });
  });
}
