import 'package:facteur/config/theme.dart';
import 'package:facteur/features/soutien/soutien_copy.dart';
import 'package:facteur/features/soutien/widgets/paywall_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> _pumpSheet(WidgetTester tester, PaywallWallVariant variant) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(child: PaywallSheet(variant: variant)),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('variante sources : headline + CTA + mission', (tester) async {
    await _pumpSheet(tester, PaywallWallVariant.sources);

    expect(find.text(SoutienCopy.sourcesWallHeadline), findsOneWidget);
    expect(find.text(SoutienCopy.wallCta), findsOneWidget);
    expect(find.text(SoutienCopy.missionLinkLabel), findsOneWidget);
    expect(find.text(SoutienCopy.wallDisclaimer), findsOneWidget);
  });

  testWidgets('variante analyses : copy quota épuisé', (tester) async {
    await _pumpSheet(tester, PaywallWallVariant.analyses);

    expect(find.text(SoutienCopy.analysesWallHeadline), findsOneWidget);
    expect(
      find.text(SoutienCopy.analysesWallEyebrow.toUpperCase()),
      findsOneWidget,
    );
  });

  testWidgets('variante serein : headline dédiée', (tester) async {
    await _pumpSheet(tester, PaywallWallVariant.serein);

    expect(find.text(SoutienCopy.sereinWallHeadline), findsOneWidget);
  });
}
