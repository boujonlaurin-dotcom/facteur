import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/sticky_tab_bar.dart';

/// Rangée type : héros figé en tête, trois sections déplaçables, Citation figée
/// en queue (cf. `_syncStickyEntries`).
const _tabs = [
  StickyTab(label: 'Ton Essentiel', accent: Color(0xFFB0470A)),
  StickyTab(
    label: 'Actus',
    accent: Color(0xFFB0470A),
    orderKey: 'essentiel',
  ),
  StickyTab(label: 'Tech', accent: Color(0xFF2C3E50), orderKey: 'theme:tech'),
  StickyTab(
    label: 'Bonnes nouvelles',
    accent: Color(0xFF2E7D32),
    orderKey: 'bonnes',
  ),
  StickyTab(label: 'Citation du jour', accent: Color(0xFFB8A898)),
];

Widget _wrap(Widget child) => ProviderScope(
      child: MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: Align(alignment: Alignment.topCenter, child: child),
        ),
      ),
    );

/// Simule un long-press (au-delà du délai de 900 ms du recognizer) suivi d'un
/// glissement horizontal de [dx] pixels sur l'onglet [label].
Future<void> _longPressDrag(
  WidgetTester tester,
  String label,
  double dx,
) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text(label)));
  await tester.pump(const Duration(milliseconds: 1100));
  // Déplacement fractionné : le proxy suit le doigt et la liste recalcule la
  // position de drop à chaque frame.
  for (var i = 0; i < 5; i++) {
    await gesture.moveBy(Offset(dx / 5, 0));
    await tester.pump(const Duration(milliseconds: 16));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('StickyTabBar — réordre par drag', () {
    testWidgets('un long-press-drag sur une section déplaçable réordonne',
        (tester) async {
      final calls = <List<int>>[];
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          onTapTab: (_) {},
          onReorder: (o, n) => calls.add([o, n]),
        ),
      ));

      await _longPressDrag(tester, 'Tech', -160);

      expect(calls, isNotEmpty, reason: 'le drag doit produire un réordre');
      expect(calls.single[0], 2, reason: 'index saisi = celui de « Tech »');
      expect(calls.single[1], lessThan(2),
          reason: 'un drag vers la gauche remonte l\'onglet');
    });

    testWidgets('un onglet figé n\'est pas saisissable', (tester) async {
      final calls = <List<int>>[];
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          onTapTab: (_) {},
          onReorder: (o, n) => calls.add([o, n]),
        ),
      ));

      await _longPressDrag(tester, 'Ton Essentiel', 200);
      await _longPressDrag(tester, 'Citation du jour', -200);

      expect(calls, isEmpty);
    });

    testWidgets('un tap court navigue toujours (le drag ne vole pas le geste)',
        (tester) async {
      var tapped = -1;
      final calls = <List<int>>[];
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          onTapTab: (i) => tapped = i,
          onReorder: (o, n) => calls.add([o, n]),
        ),
      ));

      await tester.tap(find.text('Tech'));
      await tester.pumpAndSettle();

      expect(tapped, 2);
      expect(calls, isEmpty);
    });

    testWidgets('sans callback de réordre, la rangée reste une simple liste',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(tabs: _tabs, activeIndex: 0, onTapTab: (_) {}),
      ));
      expect(find.byType(ReorderableListView), findsNothing);
      expect(find.text('Tech'), findsOneWidget);
    });

    testWidgets('un seul onglet déplaçable ⇒ pas de réordre possible',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: const [
            StickyTab(label: 'Ton Essentiel', accent: Color(0xFFB0470A)),
            StickyTab(
              label: 'Actus',
              accent: Color(0xFFB0470A),
              orderKey: 'essentiel',
            ),
          ],
          activeIndex: 0,
          onTapTab: (_) {},
          onReorder: (_, __) {},
        ),
      ));
      expect(find.byType(ReorderableListView), findsNothing);
    });
  });
}
