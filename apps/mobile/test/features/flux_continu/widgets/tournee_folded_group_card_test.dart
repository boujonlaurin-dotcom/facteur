import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/tournee_folded_group_card.dart';

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

  group('TourneeFoldedGroupCard', () {
    testWidgets('renders « Tournée du jour ✓ » title with Fraunces font',
        (tester) async {
      await tester.pumpWidget(_wrap(
        TourneeFoldedGroupCard(onTap: () {}),
      ));

      // Title text is present
      expect(find.text('Tournée du jour ✓'), findsOneWidget);
    });

    testWidgets('renders check icon and expand_more chevron', (tester) async {
      await tester.pumpWidget(_wrap(
        TourneeFoldedGroupCard(onTap: () {}),
      ));

      expect(find.byIcon(Icons.check), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('fires onTap callback when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        TourneeFoldedGroupCard(onTap: () => taps++),
      ));

      await tester.tap(find.byType(TourneeFoldedGroupCard));
      await tester.pump();

      expect(taps, 1);
    });

    testWidgets('fires onTap callback when tapped on title text',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        TourneeFoldedGroupCard(onTap: () => taps++),
      ));

      await tester.tap(find.text('Tournée du jour ✓'));
      await tester.pump();

      expect(taps, 1);
    });
  });
}
