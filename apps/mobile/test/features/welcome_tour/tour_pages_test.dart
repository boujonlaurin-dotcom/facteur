import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/welcome_tour/widgets/tour_page_essentiel.dart';
import 'package:facteur/features/welcome_tour/widgets/tour_page_feed.dart';
import 'package:facteur/features/welcome_tour/widgets/tour_page_perso.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: FacteurTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('Welcome Tour pages', () {
    testWidgets('TourPageEssentiel renders title and subtitle', (tester) async {
      await tester.pumpWidget(_wrap(const TourPageEssentiel()));
      // Animation controller starts immediately; pump one frame to avoid
      // leaving a running timer pending for the test engine.
      await tester.pump(const Duration(milliseconds: 1500));

      expect(find.text("L'Essentiel"), findsOneWidget);
      expect(
        find.textContaining('5 articles pour te sortir de ta bulle'),
        findsOneWidget,
      );
    });

    testWidgets('TourPageFeed renders title and subtitle', (tester) async {
      await tester.pumpWidget(_wrap(const TourPageFeed()));
      // Page 2's animation loops; pump a frame then stop.
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Ton flux'), findsOneWidget);
      expect(
        find.textContaining('Toutes tes sources suivies'),
        findsOneWidget,
      );
    });

    testWidgets('TourPagePerso renders title and subtitle', (tester) async {
      await tester.pumpWidget(_wrap(const TourPagePerso()));
      await tester.pump(const Duration(milliseconds: 1900));

      expect(find.text('Personnalisation'), findsOneWidget);
      expect(
        find.textContaining('Ajoute des sources'),
        findsOneWidget,
      );
    });
  });
}
