import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/sticky_tab_bar.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(body: child),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('StickyThreeStateBar', () {
    testWidgets('renders Essentiel state with title + ratio', (tester) async {
      await tester.pumpWidget(_wrap(
        const StickyThreeStateBar(
          bloc: StickyMacroBloc.essentiel,
          read: 2,
          total: 5,
          remainingMin: 6,
        ),
      ));
      expect(find.text('L’Essentiel du jour'), findsOneWidget);
      expect(find.text('2/5'), findsOneWidget);
      expect(find.text('~6 min'), findsOneWidget);
    });

    testWidgets('swaps title when bloc changes to parTheme', (tester) async {
      await tester.pumpWidget(_wrap(
        const StickyThreeStateBar(
          bloc: StickyMacroBloc.essentiel,
          read: 0,
          total: 5,
          remainingMin: 10,
        ),
      ));
      await tester.pumpWidget(_wrap(
        const StickyThreeStateBar(
          bloc: StickyMacroBloc.parTheme,
          read: 0,
          total: 8,
          remainingMin: 16,
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('L’Essentiel, par thème'), findsOneWidget);
    });

    testWidgets('shows Explorer label in explorer state', (tester) async {
      await tester.pumpWidget(_wrap(
        const StickyThreeStateBar(
          bloc: StickyMacroBloc.explorer,
          read: 0,
          total: 0,
          remainingMin: 0,
        ),
      ));
      expect(find.text('Explorer'), findsOneWidget);
    });

    testWidgets('tap fires onTap', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        StickyThreeStateBar(
          bloc: StickyMacroBloc.essentiel,
          read: 0,
          total: 5,
          remainingMin: 10,
          onTap: () => taps++,
        ),
      ));
      await tester.tap(find.text('L’Essentiel du jour'));
      expect(taps, 1);
    });
  });
}
