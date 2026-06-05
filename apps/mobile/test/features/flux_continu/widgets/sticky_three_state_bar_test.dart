import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/sticky_tab_bar.dart';

/// Tests cover the [StickyTabBar] restored by the Story 9.2 hotfix
/// (PR follow-up to #650). The file name kept its historical name so the
/// existing CI globs don't need an update.
Widget _wrap(Widget child, {Key? boundaryKey}) {
  final body = Align(alignment: Alignment.topCenter, child: child);
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
        body: boundaryKey == null
            ? body
            : RepaintBoundary(key: boundaryKey, child: body),
      ),
    ),
  );
}

/// Raw RGBA of the captured [boundaryKey] image at the centre of the progress
/// segment whose horizontal centre is at fraction [fx] of the track width.
Future<List<int>> _sampleTrack(
  WidgetTester tester,
  Key boundaryKey,
  Finder trackPaint,
  double fx,
) async {
  final rect = tester.getRect(trackPaint);
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(boundaryKey));
  // toImage() is backed by the engine; it only resolves on the real event loop,
  // so it must run inside runAsync (default pixelRatio 1.0 ⇒ image px == logical
  // px, no devicePixelRatio scaling).
  late List<int> data;
  late int width;
  await tester.runAsync(() async {
    final image = await boundary.toImage();
    data = (await image.toByteData())!.buffer.asUint8List();
    width = image.width;
  });
  final x = (rect.left + rect.width * fx).round();
  final y = rect.center.dy.round();
  final i = (y * width + x) * 4;
  return [data[i], data[i + 1], data[i + 2], data[i + 3]];
}

int _rgbaDist(List<int> a, List<int> b) {
  var d = 0;
  for (var i = 0; i < 4; i++) {
    d += (a[i] - b[i]).abs();
  }
  return d;
}

Finder get _progressTrack => find.byWidgetPredicate(
      (w) =>
          w is CustomPaint &&
          (w.painter?.runtimeType.toString().contains('ProgressPainter') ??
              false),
    );

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
          onTapTab: (i) => lastTapped = i,
        ),
      ));
      await tester.tap(find.text('Tech'));
      expect(lastTapped, 1);
    });

    testWidgets('active tab paints a felt-tip marker behind its label',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          onTapTab: (_) {},
        ),
      ));
      // The active tab (index 0) paints a felt-tip "surligneur" stroke behind
      // its **label text** via a dedicated CustomPainter (remplace l'ancien chip
      // plat + le wash pleine-chip + le point). Exactly one such marker painter
      // should be present (one active tab).
      final markerPainters =
          tester.widgetList<CustomPaint>(find.byType(CustomPaint)).where((cp) {
        final painter = cp.painter;
        return painter != null &&
            painter.runtimeType.toString().contains('MarkerHighlight');
      });
      expect(markerPainters, hasLength(1));
    });

    testWidgets(
        'progress track is segmented: 1 done + 1 current filled, 1 upcoming muted',
        (tester) async {
      const boundaryKey = ValueKey('progress-boundary');
      // activeIndex = 1, 3 tabs ⇒ segment 0 done, segment 1 current (both
      // colour-filled), segment 2 upcoming (muted track colour).
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 1,
          onTapTab: (_) {},
        ),
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();
      expect(_progressTrack, findsOneWidget);

      // Sample the centre of each of the three pips.
      final done = await _sampleTrack(tester, boundaryKey, _progressTrack, 1 / 6);
      final current =
          await _sampleTrack(tester, boundaryKey, _progressTrack, 3 / 6);
      final upcoming =
          await _sampleTrack(tester, boundaryKey, _progressTrack, 5 / 6);

      // The upcoming pip (muted track over parchment) is visibly distinct from
      // both the filled done and current pips — the segmentation boundary the
      // user reads as "pages".
      expect(_rgbaDist(upcoming, done), greaterThan(24),
          reason: 'upcoming should differ from the filled done pip');
      expect(_rgbaDist(upcoming, current), greaterThan(24),
          reason: 'upcoming should differ from the filled current pip');
    });

    testWidgets(
        'a previously-upcoming segment fills once it becomes current/done',
        (tester) async {
      const boundaryKey = ValueKey('progress-boundary-2');
      // First capture the last segment while it is upcoming (activeIndex = 1).
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 1,
          onTapTab: (_) {},
        ),
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();
      final whenUpcoming =
          await _sampleTrack(tester, boundaryKey, _progressTrack, 5 / 6);

      // Now make it the current segment (activeIndex = 2) — it must fill.
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 2,
          onTapTab: (_) {},
        ),
        boundaryKey: boundaryKey,
      ));
      await tester.pumpAndSettle();
      final whenCurrent =
          await _sampleTrack(tester, boundaryKey, _progressTrack, 5 / 6);

      expect(_rgbaDist(whenUpcoming, whenCurrent), greaterThan(24),
          reason: 'the segment colour must change with activeIndex');
    });

    testWidgets('no leading dot before tab labels (removed in marker redesign)',
        (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
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
