import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/widgets/perspectives_pill.dart';

/// Tests pour le gate backend `should_display` du post-filtre Comparaison.
/// Cf. docs/bugs/bug-comparison-clustering-too-loose.md
void main() {
  group('PerspectivesResponse.fromJson — should_display', () {
    Map<String, dynamic> baseJson({bool? shouldDisplay}) {
      final json = <String, dynamic>{
        'perspectives': <dynamic>[],
        'keywords': <String>[],
        'bias_distribution': <String, dynamic>{'left': 1, 'center': 1, 'right': 1},
        'source_bias_stance': 'center',
        'comparison_quality': 'high',
      };
      if (shouldDisplay != null) json['should_display'] = shouldDisplay;
      return json;
    }

    test('parses should_display=true', () {
      final r = PerspectivesResponse.fromJson(baseJson(shouldDisplay: true));
      expect(r.shouldDisplay, isTrue);
    });

    test('parses should_display=false', () {
      final r = PerspectivesResponse.fromJson(baseJson(shouldDisplay: false));
      expect(r.shouldDisplay, isFalse);
    });

    test('defaults to false when field missing (legacy payload)', () {
      final r = PerspectivesResponse.fromJson(baseJson());
      expect(r.shouldDisplay, isFalse);
    });
  });

  group('PerspectivesPill — CTA état isEmpty (gate should_display=false)', () {
    Widget host(Widget child) => MaterialApp(
          theme: FacteurTheme.darkTheme,
          home: Scaffold(body: Center(child: child)),
        );

    testWidgets('isEmpty=true → FAB désactivé (onPressed == null)',
        (tester) async {
      await tester.pumpWidget(host(PerspectivesPill(
        biasDistribution: const {},
        isLoading: false,
        isEmpty: true,
        onTap: () {},
      )));
      // Fait tourner l'entrance animation (delay 1s + 500ms curve).
      await tester.pump(const Duration(seconds: 2));

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
    });

    testWidgets('isEmpty=false + isLoading=false → FAB actif, onPressed invoque onTap',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(PerspectivesPill(
        biasDistribution: const {'left': 1, 'center': 1, 'right': 1},
        isLoading: false,
        isEmpty: false,
        onTap: () => taps++,
      )));
      await tester.pump(const Duration(seconds: 2));

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNotNull);
      fab.onPressed!();
      expect(taps, 1);
    });

    testWidgets('isLoading=true → FAB désactivé même si !isEmpty',
        (tester) async {
      await tester.pumpWidget(host(PerspectivesPill(
        biasDistribution: const {'left': 1},
        isLoading: true,
        isEmpty: false,
        onTap: () {},
      )));
      await tester.pump(const Duration(seconds: 2));

      final fab = tester.widget<FloatingActionButton>(
        find.byType(FloatingActionButton),
      );
      expect(fab.onPressed, isNull);
    });
  });
}
