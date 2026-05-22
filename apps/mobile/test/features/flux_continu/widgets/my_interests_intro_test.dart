import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/my_interests_intro.dart';

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

  group('MyInterestsIntro', () {
    testWidgets('uses plural copy when 2 favorites and fires manage callback',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(_wrap(
        MyInterestsIntro(favoriteCount: 2, onTapManage: () => taps++),
      ));

      expect(find.text('TES 2 THÈMES FAVORIS'), findsOneWidget);
      expect(find.text('GÉRER'), findsOneWidget);

      await tester.tap(find.text('GÉRER'));
      await tester.pump();
      expect(taps, 1);
    });

    testWidgets('uses singular copy when 1 favorite', (tester) async {
      await tester.pumpWidget(_wrap(
        MyInterestsIntro(favoriteCount: 1, onTapManage: () {}),
      ));
      expect(find.text('TON THÈME FAVORI'), findsOneWidget);
    });
  });
}
