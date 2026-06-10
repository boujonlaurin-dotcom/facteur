import 'package:facteur/shared/widgets/navigation/swipe_back_page.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const viewportSize = Size(800, 600);

  Future<void> openScrollablePage(
    WidgetTester tester, {
    ScrollController? controller,
    VoidCallback? onLeftTap,
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
                      child: _ScrollableTestPage(
                        controller: controller,
                        onLeftTap: onLeftTap,
                      ),
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
    expect(find.text('Page scrollable'), findsOneWidget);
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
