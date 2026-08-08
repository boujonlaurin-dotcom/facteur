import 'package:facteur/shared/widgets/navigation/swipe_back_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewportSize = Size(800, 600);

  Future<void> openPage(
    WidgetTester tester, {
    required Widget page,
    required String marker,
    double widthFraction = wideBackGestureWidthFraction,
  }) async {
    await tester.binding.setSurfaceSize(viewportSize);
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () {
                  Navigator.of(context).push(
                    FullSwipeCupertinoPage<void>(
                      backGestureWidthFraction: widthFraction,
                      child: page,
                    ).createRoute(context),
                  );
                },
                child: const Text('Ouvrir'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Ouvrir'));
    await tester.pumpAndSettle();
    expect(find.text(marker), findsOneWidget);
  }

  Future<void> openScrollablePage(
    WidgetTester tester, {
    ScrollController? controller,
    VoidCallback? onLeftTap,
    double widthFraction = wideBackGestureWidthFraction,
  }) {
    return openPage(
      tester,
      widthFraction: widthFraction,
      marker: 'Page scrollable',
      page: _ScrollableTestPage(
        controller: controller,
        onLeftTap: onLeftTap,
      ),
    );
  }

  Future<void> openPagedPage(WidgetTester tester) {
    return openPage(
      tester,
      widthFraction: edgeBackGestureWidthFraction,
      marker: 'Page 0',
      page: const _PagedTestPage(),
    );
  }

  Future<void> dragFrom(WidgetTester tester, Offset start, Offset delta) async {
    final gesture = await tester.startGesture(start);
    const steps = 10;
    for (var step = 0; step < steps; step++) {
      await gesture.moveBy(delta / steps.toDouble());
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  group('FullSwipeCupertinoPage', () {
    testWidgets('allows vertical scrolling from the left, center and right', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await openScrollablePage(
        tester,
        controller: controller,
      );

      for (final x in <double>[40, 400, 760]) {
        controller.jumpTo(0);
        await tester.pump();

        await dragFrom(tester, Offset(x, 450), const Offset(0, -220));

        expect(
          controller.offset,
          greaterThan(0),
          reason: 'A vertical drag starting at x=$x should scroll.',
        );
        expect(find.text('Page scrollable'), findsOneWidget);
      }
    });

    testWidgets('keeps a mostly vertical diagonal drag in the scroll view', (
      tester,
    ) async {
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await openScrollablePage(tester, controller: controller);

      await dragFrom(tester, const Offset(40, 450), const Offset(30, -220));

      expect(controller.offset, greaterThan(0));
      expect(find.text('Page scrollable'), findsOneWidget);
    });

    testWidgets('pops on a right swipe starting in the left 35 percent', (
      tester,
    ) async {
      await openScrollablePage(tester);

      await dragFrom(tester, const Offset(40, 300), const Offset(500, 0));

      expect(find.text('Page scrollable'), findsNothing);
      expect(find.text('Ouvrir'), findsOneWidget);
    });

    testWidgets('does not pop when the right swipe starts outside the zone', (
      tester,
    ) async {
      await openScrollablePage(tester);

      await dragFrom(tester, const Offset(400, 300), const Offset(300, 0));

      expect(find.text('Page scrollable'), findsOneWidget);
    });

    testWidgets('keeps taps interactive inside the left gesture zone', (
      tester,
    ) async {
      var tapCount = 0;
      await openScrollablePage(tester, onLeftTap: () => tapCount++);

      await tester.tap(find.byKey(const Key('left-button')));
      await tester.pump();

      expect(tapCount, 1);
      expect(find.text('Page scrollable'), findsOneWidget);
    });

    testWidgets(
      'bande de bord : le retour ne part plus que du bord de l’écran',
      (tester) async {
        await openScrollablePage(
          tester,
          widthFraction: edgeBackGestureWidthFraction,
        );

        // 200 px = dans l’ancienne zone large (35 % de 800), hors de la bande.
        await dragFrom(tester, const Offset(200, 300), const Offset(400, 0));
        expect(find.text('Page scrollable'), findsOneWidget);

        await dragFrom(tester, const Offset(10, 300), const Offset(500, 0));
        expect(find.text('Page scrollable'), findsNothing);
        expect(find.text('Ouvrir'), findsOneWidget);
      },
    );

    testWidgets(
      'un PageView horizontal dans la page ne vole pas la bande de retour',
      (tester) async {
        // Régression du deck d’articles (Story 34.1) : deux recognizers
        // horizontaux en concurrence. La bande étant posée au-dessus de la
        // page, son recognizer entre dans l’arène en premier et gagne.
        await openPagedPage(tester);

        // Au centre, c’est le PageView qui doit répondre.
        await dragFrom(tester, const Offset(400, 300), const Offset(-500, 0));
        expect(find.text('Page 1'), findsOneWidget);
        expect(find.text('Ouvrir'), findsNothing);

        // Sur la bande de bord, c’est le retour.
        await dragFrom(tester, const Offset(10, 300), const Offset(500, 0));
        expect(find.text('Ouvrir'), findsOneWidget);
      },
    );

    test('platform views claim vertical drags only', () {
      final recognizers = swipeBackCompatiblePlatformViewGestureRecognizers();
      expect(recognizers, hasLength(1));
      expect(
        recognizers.single.type,
        VerticalDragGestureRecognizer,
      );
    });
  });
}

/// Page portant son propre geste horizontal — miroir du deck d'articles.
class _PagedTestPage extends StatelessWidget {
  const _PagedTestPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: PageView.builder(
        itemCount: 3,
        itemBuilder: (context, index) => ColoredBox(
          color: Colors.white,
          child: Center(child: Text('Page $index')),
        ),
      ),
    );
  }
}

class _ScrollableTestPage extends StatelessWidget {
  const _ScrollableTestPage({
    this.controller,
    this.onLeftTap,
  });

  final ScrollController? controller;
  final VoidCallback? onLeftTap;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page scrollable')),
      body: Stack(
        children: [
          ListView.builder(
            controller: controller,
            itemExtent: 80,
            itemCount: 30,
            itemBuilder: (context, index) => Text('Ligne $index'),
          ),
          Positioned(
            left: 8,
            top: 8,
            child: FilledButton(
              key: const Key('left-button'),
              onPressed: onLeftTap,
              child: const Text('Action gauche'),
            ),
          ),
        ],
      ),
    );
  }
}
