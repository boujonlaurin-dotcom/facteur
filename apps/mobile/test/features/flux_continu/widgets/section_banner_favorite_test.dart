import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/section_banner.dart';

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

  group('SectionBanner favorite star', () {
    testWidgets('omits the star when onTapFavorite is null', (tester) async {
      await tester.pumpWidget(_wrap(
        const SectionBanner(
          title: 'L\'Essentiel du jour',
          accent: Color(0xFFB0470A),
          blurb: 'Pour comprendre ce qui compte.',
        ),
      ));

      // No star icon — the layout is identical to the legacy V1.8 banner.
      expect(find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.fill)),
          findsNothing);
    });

    testWidgets('renders the star and fires onTapFavorite', (tester) async {
      var favoriteTaps = 0;

      await tester.pumpWidget(_wrap(
        SectionBanner(
          title: 'Climat',
          accent: const Color(0xFF6C3483),
          blurb: 'Ta veille climat — sourcée, lente, sans panique.',
          onTapFavorite: () => favoriteTaps++,
        ),
      ));

      final starFinder =
          find.byIcon(PhosphorIcons.star(PhosphorIconsStyle.fill));
      expect(starFinder, findsOneWidget);

      await tester.tap(starFinder, warnIfMissed: false);
      await tester.pump();

      expect(favoriteTaps, 1);
    });
  });
}
