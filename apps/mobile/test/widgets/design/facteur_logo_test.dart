import 'package:facteur/config/theme.dart';
import 'package:facteur/widgets/design/facteur_logo.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

/// Bug 4 : le widget doit rendre le **logo officiel** (SVG vectoriel), pas la
/// variante app-icon PNG perdue par #882, et ne teinter le logo que lorsqu'une
/// couleur custom est explicitement demandée.
void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  Widget host(Widget child) => MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(body: Center(child: child)),
      );

  testWidgets('renders the official SVG logo by default (no color filter)',
      (tester) async {
    await tester.pumpWidget(host(const FacteurLogo()));

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    final loader = svg.bytesLoader as SvgAssetLoader;
    expect(loader.assetName, 'assets/icons/logo_officiel.svg');
    // Par défaut (effectiveColor == textPrimary), pas de teinte : le logo
    // est rendu dans ses vraies couleurs.
    expect(svg.colorFilter, isNull);
  });

  testWidgets('applies a color filter when a custom color is passed',
      (tester) async {
    await tester.pumpWidget(host(const FacteurLogo(color: Color(0xFFFF0000))));

    final svg = tester.widget<SvgPicture>(find.byType(SvgPicture));
    expect(svg.colorFilter, isNotNull);
  });

  testWidgets('showText:false renders the icon only', (tester) async {
    await tester.pumpWidget(host(const FacteurLogo(showText: false)));

    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.text('Facteur'), findsNothing);
  });
}
