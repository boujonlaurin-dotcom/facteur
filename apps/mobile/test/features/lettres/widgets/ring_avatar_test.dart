import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/lettres/widgets/ring_avatar.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(
      backgroundColor: FacteurPalettes.light.backgroundPrimary,
      body: Center(child: child),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('RingAvatar.fromName initials', () {
    test('null fullName falls back to F', () {
      expect(RingAvatar.fromName(null, null).initials, 'F');
    });

    test('empty/blank fullName falls back to F', () {
      expect(RingAvatar.fromName('', null).initials, 'F');
      expect(RingAvatar.fromName('   ', null).initials, 'F');
    });

    test('single word takes first letter', () {
      expect(RingAvatar.fromName('Laurin', null).initials, 'L');
    });

    test('two words take first letter of each, capped at 2', () {
      expect(RingAvatar.fromName('Laurin Boujon', null).initials, 'LB');
      expect(
        RingAvatar.fromName('Jean-Pierre De La Fontaine', null).initials,
        'JD',
      );
    });

    test('lowercase input is uppercased', () {
      expect(RingAvatar.fromName('laurin boujon', null).initials, 'LB');
    });
  });

  group('RingAvatar goldens', () {
    testWidgets('null progress — no ring', (tester) async {
      await tester.pumpWidget(_wrap(
        const RingAvatar(initials: 'LB', progress: null),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(RingAvatar),
        matchesGoldenFile('goldens/ring_avatar_null.png'),
      );
    });

    testWidgets('progress 0.02 — minimal ring', (tester) async {
      await tester.pumpWidget(_wrap(
        const RingAvatar(initials: 'LB', progress: 0.02),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(RingAvatar),
        matchesGoldenFile('goldens/ring_avatar_002.png'),
      );
    });

    testWidgets('progress 0.5 — half ring', (tester) async {
      await tester.pumpWidget(_wrap(
        const RingAvatar(initials: 'LB', progress: 0.5),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(RingAvatar),
        matchesGoldenFile('goldens/ring_avatar_050.png'),
      );
    });

    testWidgets('progress 1.0 — full ring', (tester) async {
      await tester.pumpWidget(_wrap(
        const RingAvatar(initials: 'LB', progress: 1.0),
      ));
      await tester.pumpAndSettle();
      await expectLater(
        find.byType(RingAvatar),
        matchesGoldenFile('goldens/ring_avatar_100.png'),
      );
    });
  });
}
