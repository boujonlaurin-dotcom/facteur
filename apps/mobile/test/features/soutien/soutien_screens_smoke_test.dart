import 'package:facteur/config/theme.dart';
import 'package:facteur/features/soutien/screens/link_sent_screen.dart';
import 'package:facteur/features/soutien/screens/soutien_screen.dart';
import 'package:facteur/features/soutien/screens/veille_wall_screen.dart';
import 'package:facteur/features/soutien/soutien_copy.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

Widget _host(Widget screen) {
  final router = GoRouter(
    routes: [GoRoute(path: '/', builder: (_, __) => screen)],
  );
  return ProviderScope(
    child: MaterialApp.router(
      theme: FacteurTheme.lightTheme,
      routerConfig: router,
    ),
  );
}

void main() {
  testWidgets('Soutien : lettre, bonus, prix et CTA', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 2000 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const SoutienScreen()));
    await tester.pumpAndSettle();

    expect(find.text(SoutienCopy.soutienHeadline), findsOneWidget);
    expect(find.text(SoutienCopy.soutienEyebrow), findsOneWidget);
    expect(find.text(SoutienCopy.soutienCta), findsOneWidget);
    expect(find.text(SoutienCopy.priceAmount), findsOneWidget);
    expect(find.textContaining('BIENTÔT'), findsNWidgets(2));
  });

  testWidgets('Mur veille : bénéfices + CTA débloquer', (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 1600 * 3);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(const VeilleWallScreen()));
    await tester.pumpAndSettle();

    expect(find.text(SoutienCopy.veilleWallHeadline), findsOneWidget);
    expect(find.text(SoutienCopy.wallCta), findsOneWidget);
    expect(find.text(SoutienCopy.missionLinkLabel), findsOneWidget);
  });

  testWidgets('Lien envoyé : cachet + retour + renvoyer', (tester) async {
    await tester.pumpWidget(_host(const LinkSentScreen()));
    await tester.pumpAndSettle();

    expect(find.text(SoutienCopy.linkSentHeadline), findsOneWidget);
    expect(find.text(SoutienCopy.linkSentStamp), findsOneWidget);
    expect(find.text(SoutienCopy.linkSentBack), findsOneWidget);
    expect(find.text(SoutienCopy.linkSentResend), findsOneWidget);
  });
}
