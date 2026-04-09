import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/feed_refresh_undo_banner.dart';

/// Tests unitaires du bandeau discret affiché après un pull-to-refresh.
/// Story 4.5b — Feed Refresh Viewport-Aware + Undo.
void main() {
  Widget makeHost(Widget child) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SafeArea(child: Align(alignment: Alignment.topCenter, child: child)),
      ),
    );
  }

  group('FeedRefreshUndoBanner', () {
    testWidgets('displays the refresh label + undo button', (tester) async {
      await tester.pumpWidget(makeHost(FeedRefreshUndoBanner(
        onUndo: () {},
        onAutoResolve: () {},
        autoDismissDuration: const Duration(seconds: 6),
      )));

      // Wait a frame for fade-in animation to start.
      await tester.pump();

      expect(find.text('Feed rafraîchi'), findsOneWidget);
      expect(find.text('Annuler'), findsOneWidget);
    });

    testWidgets('tap on Annuler triggers onUndo then onAutoResolve',
        (tester) async {
      int undoCalls = 0;
      int resolveCalls = 0;

      await tester.pumpWidget(makeHost(FeedRefreshUndoBanner(
        onUndo: () => undoCalls++,
        onAutoResolve: () => resolveCalls++,
        autoDismissDuration: const Duration(seconds: 6),
      )));
      await tester.pump();

      await tester.tap(find.text('Annuler'));
      // Wait for the fade-out to complete (250ms).
      await tester.pump(const Duration(milliseconds: 300));

      expect(undoCalls, 1);
      expect(resolveCalls, 1);
    });

    testWidgets('auto-dismisses after autoDismissDuration', (tester) async {
      int undoCalls = 0;
      int resolveCalls = 0;

      await tester.pumpWidget(makeHost(FeedRefreshUndoBanner(
        onUndo: () => undoCalls++,
        onAutoResolve: () => resolveCalls++,
        autoDismissDuration: const Duration(milliseconds: 500),
      )));
      await tester.pump();

      // Not yet expired.
      expect(resolveCalls, 0);

      // Advance past dismiss timer + fade-out animation (250ms).
      await tester.pump(const Duration(milliseconds: 550));
      await tester.pump(const Duration(milliseconds: 300));

      expect(undoCalls, 0);
      expect(resolveCalls, 1);
    });

    testWidgets('auto-resolve fires only once even if widget rebuilds',
        (tester) async {
      int resolveCalls = 0;

      await tester.pumpWidget(makeHost(FeedRefreshUndoBanner(
        onUndo: () {},
        onAutoResolve: () => resolveCalls++,
        autoDismissDuration: const Duration(milliseconds: 200),
      )));
      await tester.pump();

      // Let auto-resolve + animation run.
      await tester.pump(const Duration(milliseconds: 250));
      await tester.pump(const Duration(milliseconds: 300));

      expect(resolveCalls, 1);

      // Pump extra frames to ensure timer doesn't re-fire.
      await tester.pump(const Duration(milliseconds: 500));
      expect(resolveCalls, 1);
    });

    // Regression for M2: tapping Annuler during the auto-dismiss fade-out must
    // not fire onAutoResolve a second time (the _resolved flag guards this).
    testWidgets(
        'tapping Annuler while auto-dismiss is animating fires onAutoResolve exactly once',
        (tester) async {
      int undoCalls = 0;
      int resolveCalls = 0;

      await tester.pumpWidget(makeHost(FeedRefreshUndoBanner(
        onUndo: () => undoCalls++,
        onAutoResolve: () => resolveCalls++,
        // Very short timer so auto-resolve fires during test.
        autoDismissDuration: const Duration(milliseconds: 100),
      )));
      await tester.pump();

      // Let the auto-dismiss timer fire but DON'T finish the fade-out yet.
      await tester.pump(const Duration(milliseconds: 120));
      // Auto-resolve started; fade-out is in progress (250ms animation).
      // Now the user taps Annuler during the animation window.
      // The _resolved flag must make _handleUndo a no-op.
      await tester.tap(find.text('Annuler'), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 300));

      // Auto-resolve already owned the flow: onAutoResolve fires exactly once,
      // onUndo is NOT triggered (user lost the race to auto-dismiss).
      expect(resolveCalls, 1);
      expect(undoCalls, 0);
    });

    // Regression for M2 (inverse): tapping Annuler BEFORE the timer fires
    // must prevent the auto-resolve from triggering a second onAutoResolve.
    testWidgets(
        'auto-timer fires after Annuler tapped — onAutoResolve fires exactly once',
        (tester) async {
      int undoCalls = 0;
      int resolveCalls = 0;

      await tester.pumpWidget(makeHost(FeedRefreshUndoBanner(
        onUndo: () => undoCalls++,
        onAutoResolve: () => resolveCalls++,
        autoDismissDuration: const Duration(milliseconds: 400),
      )));
      await tester.pump();

      // Tap before the timer fires.
      await tester.tap(find.text('Annuler'));
      await tester.pump(const Duration(milliseconds: 50));

      // Let the fade-out and then the timer's scheduled time both elapse.
      await tester.pump(const Duration(milliseconds: 600));

      expect(undoCalls, 1);
      expect(resolveCalls, 1); // only one call despite timer firing after tap
    });
  });
}
