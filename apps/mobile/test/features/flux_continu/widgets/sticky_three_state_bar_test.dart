import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/sticky_tab_bar.dart';

/// Tests cover the [StickyTabBar] restored by the Story 9.2 hotfix
/// (PR follow-up to #650). The file name kept its historical name so the
/// existing CI globs don't need an update.
Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(
        // Sticky overlay is rendered at the very top of the screen in
        // production via `Positioned(top:0, left:0, right:0)` — its inner
        // Column sizes vertically to its children (mainAxisSize.min).
        // Wrapping the test fixture in a top-aligned Align keeps the layout
        // faithful and lets the FeedFilterBar variant compute its natural
        // height without being stretched to fill the Scaffold body.
        body: Align(alignment: Alignment.topCenter, child: child),
      ),
    ),
  );
}

const _tabs = [
  StickyTab(label: 'Essentiel', accent: Color(0xFFB0470A)),
  StickyTab(label: 'Tech', accent: Color(0xFF2C3E50)),
  StickyTab(label: 'Flâner', accent: Color(0xFF5D4037)),
];

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('StickyTabBar', () {
    testWidgets('renders every tab label (no head title)', (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          progress: 0.2,
          onTapTab: (_) {},
        ),
      ));
      // The sticky no longer carries a zone title — only the tab labels.
      expect(find.text('Tournée du jour'), findsNothing);
      expect(find.text('Essentiel'), findsOneWidget);
      expect(find.text('Tech'), findsOneWidget);
      expect(find.text('Flâner'), findsOneWidget);
    });

    testWidgets('shows a check icon next to done tabs (no strike-through)',
        (tester) async {
      // activeIndex = 2 → tabs 0 and 1 are done, tab 2 is active, no
      // upcoming tabs in this fixture.
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 2,
          progress: 0.9,
          onTapTab: (_) {},
        ),
      ));
      // Two check icons (one per done tab).
      expect(find.byIcon(Icons.check_rounded), findsNWidgets(2));
      // No strike-through anywhere — we deliberately render labels without
      // the lineThrough decoration since the hotfix.
      final essentielText = tester.widget<Text>(find.text('Essentiel'));
      expect(essentielText.style?.decoration, isNot(TextDecoration.lineThrough));
    });

    testWidgets('tapping a tab fires onTapTab with its index', (tester) async {
      var lastTapped = -1;
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          progress: 0.0,
          onTapTab: (i) => lastTapped = i,
        ),
      ));
      await tester.tap(find.text('Tech'));
      expect(lastTapped, 1);
    });

    testWidgets('active tab highlights its label text with an accent marker',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          progress: 0.2,
          onTapTab: (_) {},
        ),
      ));
      // The active tab (index 0) highlights its **label text** with a
      // marker-style Container tinted with its own accent (calque du highlight
      // "Couverture médiatique" — cf. DiffTitle). The legacy full-chip wash and
      // the leading dot are gone. Exactly one marker should be present.
      final expectedMarker = const Color(0xFFB0470A).withValues(alpha: 0.22);
      final markers =
          tester.widgetList<Container>(find.byType(Container)).where((c) {
        final deco = c.decoration;
        return deco is BoxDecoration && deco.color == expectedMarker;
      });
      expect(markers, hasLength(1));
    });

    testWidgets('no leading dot before tab labels (removed in marker redesign)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          progress: 0.2,
          onTapTab: (_) {},
        ),
      ));
      // The legacy 9×9 circle dot is gone — no BoxShape.circle decorations
      // should remain in the tab row.
      final dots =
          tester.widgetList<Container>(find.byType(Container)).where((c) {
        final deco = c.decoration;
        return deco is BoxDecoration && deco.shape == BoxShape.circle;
      });
      expect(dots, isEmpty);
    });
  });
}
