import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive_flutter/hive_flutter.dart';

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
  late Directory tempDir;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    // StickyHead renders a ProfileAvatarButton, which reads providers backed
    // by Hive (user profile cache). Initialize Hive against a temp dir so the
    // avatar can build; Supabase stays uninitialized and is handled gracefully
    // by the providers (auth-less → default/empty state).
    tempDir = await Directory.systemTemp.createTemp('sticky_tab_bar_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  group('StickyTabBar', () {
    testWidgets('renders the head title + every tab label', (tester) async {
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 0,
          progress: 0.2,
          onTapTab: (_) {},
        ),
      ));
      expect(find.text('Tournée du jour'), findsOneWidget);
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

    testWidgets('switches head title to "Flâner" in Explorer mode',
        (tester) async {
      // `showFilterBar: false` here — we only assert on the head title
      // swap. The full filter-bar variant pulls in Riverpod-backed feed
      // providers, which is covered by the integration tests instead.
      await tester.pumpWidget(_wrap(
        StickyTabBar(
          tabs: _tabs,
          activeIndex: 2,
          progress: 1.0,
          onTapTab: (_) {},
          title: 'Flâner',
        ),
      ));
      // Head title becomes Flâner and the last tab keeps the same label.
      expect(find.text('Flâner'), findsNWidgets(2));
    });
  });
}
