import 'package:facteur/config/theme.dart';
import 'package:facteur/features/soutien/providers/premium_gate_provider.dart';
import 'package:facteur/features/soutien/soutien_copy.dart';
import 'package:facteur/features/veille/screens/veille_intro_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host({required bool isPremium}) {
  return ProviderScope(
    overrides: [
      premiumGateProvider.overrideWithValue(
        PremiumGate(isPremium: isPremium, followedSourcesCount: 0),
      ),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: VeilleIntroScreen(onClose: () {}, onStart: () {}),
      ),
    ),
  );
}

void main() {
  testWidgets('free : stamp réservé + CTA verrouillé vers le mur veille',
      (tester) async {
    await tester.pumpWidget(_host(isPremium: false));
    await tester.pumpAndSettle();

    expect(find.text(SoutienCopy.veilleGateStamp), findsOneWidget);
    expect(find.text(SoutienCopy.veilleGateCta), findsOneWidget);
    expect(find.text("C'est parti"), findsNothing);
  });

  testWidgets('premium : CTA normal, pas de stamp', (tester) async {
    await tester.pumpWidget(_host(isPremium: true));
    await tester.pumpAndSettle();

    expect(find.text(SoutienCopy.veilleGateStamp), findsNothing);
    expect(find.text("C'est parti"), findsOneWidget);
  });
}
