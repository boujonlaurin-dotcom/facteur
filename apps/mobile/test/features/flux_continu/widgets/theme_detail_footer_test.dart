import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/widgets/theme_detail_footer.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(body: child),
  );
}

FeedThemeSection _section(String label) => FeedThemeSection(
      kind: SectionKind.theme,
      label: label,
      accent: const Color(0xFF2C3E50),
      coreVisibleCount: 2,
      themeSlug: label.toLowerCase(),
      items: const <Content>[],
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('ThemeDetailFooter', () {
    testWidgets('without nextSection shows only the "Retour" primary CTA',
        (tester) async {
      var backTaps = 0;
      await tester.pumpWidget(_wrap(
        ThemeDetailFooter(
          sectionLabel: 'Tech',
          nextSection: null,
          onTapBackToTournee: () => backTaps++,
        ),
      ));

      expect(find.text('Vous avez fait le tour de Tech'), findsOneWidget);
      expect(find.text('Retour à la Tournée'), findsOneWidget);
      expect(find.textContaining('Sujet suivant'), findsNothing);

      await tester.tap(find.text('Retour à la Tournée'));
      expect(backTaps, 1);
    });

    testWidgets('with nextSection shows both CTAs and routes taps correctly',
        (tester) async {
      var backTaps = 0;
      var nextTaps = 0;
      final next = _section('Climat');

      await tester.pumpWidget(_wrap(
        ThemeDetailFooter(
          sectionLabel: 'Tech',
          nextSection: next,
          onTapBackToTournee: () => backTaps++,
          onTapNextSection: () => nextTaps++,
        ),
      ));

      expect(find.text('Sujet suivant : Climat →'), findsOneWidget);
      expect(find.text('Retour à la Tournée'), findsOneWidget);

      await tester.tap(find.text('Sujet suivant : Climat →'));
      expect(nextTaps, 1);
      expect(backTaps, 0);

      await tester.tap(find.text('Retour à la Tournée'));
      expect(backTaps, 1);
    });
  });
}
