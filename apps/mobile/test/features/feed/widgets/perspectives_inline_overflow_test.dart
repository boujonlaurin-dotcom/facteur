import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show DisplayGates;
import 'package:facteur/features/feed/widgets/consensus_widgets.dart';
import 'package:facteur/features/feed/widgets/coverage_spectrum_bar.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

// sourceDomain vide → fallback, pas d'Image.network en test.
Perspective _p(String name, {String bias = 'center'}) => Perspective(
      title: 'Titre $name avec un libellé un peu plus long que la moyenne',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: bias,
    );

void main() {
  Future<void> pumpAtWidth(WidgetTester tester, double width) async {
    tester.view.physicalSize = Size(width * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: width,
              child: PerspectivesInlineSection(
                status: PerspectivesSectionStatus.ready,
                perspectives: [
                  _p('Libération', bias: 'left'),
                  _p('France 24', bias: 'center-left'),
                  _p('Les Échos', bias: 'center-right'),
                  _p('Le Monde', bias: 'center'),
                  _p('Le Figaro', bias: 'right'),
                ],
                coverageCount: 6,
                biasDistribution: const {
                  'left': 1,
                  'center-left': 1,
                  'center': 1,
                  'center-right': 1,
                  'right': 1,
                },
                contentId: 'test',
                divergenceLevel: 'medium',
                display: DisplayGates.fromCoverageCount(6),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));
  }

  for (final width in [320.0, 390.0]) {
    testWidgets(
        'header + carrousel : titre complet et aucun overflow en ${width.toInt()}px',
        (tester) async {
      await pumpAtWidth(tester, width);

      final exception = tester.takeException();
      expect(
        exception,
        isNull,
        reason: 'Le header + carrousel ne doit pas déborder en ${width}px '
            '(exception capturée : $exception)',
      );

      final titleRender = tester.renderObject<RenderParagraph>(
        find.textContaining(consensusSectionTitle, findRichText: true),
      );
      expect(titleRender.didExceedMaxLines, isFalse);

      // La barre de biais est descendue en pied de bande, pleine largeur
      // (padding latéral 18 de part et d'autre).
      final spectrumSize = tester.getSize(find.byType(CoverageSpectrumBar));
      expect(spectrumSize.width, closeTo(width - 36, 1.0));
    });
  }

  testWidgets(
    'plus de huit alternatives restent consultables dans la liste virtualisée',
    (tester) async {
      tester.view.physicalSize = const Size(390 * 3, 844 * 3);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final perspectives = [
        for (var i = 1; i <= 10; i++)
          _p('Source $i', bias: i == 10 ? 'right' : 'left'),
      ];
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: Scaffold(
              body: PerspectivesInlineSection(
                status: PerspectivesSectionStatus.ready,
                perspectives: perspectives,
                coverageCount: 11,
                biasDistribution: const {'left': 9, 'right': 1},
                contentId: 'many-sources',
                display: DisplayGates.fromCoverageCount(11),
              ),
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      final carousel = find.byType(ListView);
      expect(carousel, findsOneWidget);
      expect(find.text('Source 10'), findsNothing);

      await tester.scrollUntilVisible(
        find.text('Source 10'),
        700,
        scrollable: find.descendant(
          of: carousel,
          matching: find.byType(Scrollable),
        ),
      );
      expect(find.text('Source 10'), findsOneWidget);

      final scrollable = tester.state<ScrollableState>(
        find.descendant(of: carousel, matching: find.byType(Scrollable)),
      );
      final farRightOffset = scrollable.position.pixels;
      expect(farRightOffset, greaterThan(0));
      final spectrum = tester.widget<CoverageSpectrumBar>(
        find.byType(CoverageSpectrumBar),
      );
      spectrum.onSegmentTap!('left');
      await tester.pumpAndSettle();
      expect(scrollable.position.pixels, lessThan(farRightOffset));
    },
  );

  testWidgets('les sources unknown sont groupées après Autres sources', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: PerspectivesInlineSection(
              status: PerspectivesSectionStatus.ready,
              perspectives: [
                _p('Connue', bias: 'center'),
                _p('Inconnue A', bias: 'unknown'),
                _p('Inconnue B', bias: 'unknown'),
              ],
              coverageCount: 4,
              biasDistribution: const {'center': 1},
              contentId: 'mixed',
              display: DisplayGates.fromCoverageCount(4),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    await tester.scrollUntilVisible(
      find.text('Autres sources'),
      300,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Autres sources'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Inconnue B'),
      500,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Inconnue B'), findsOneWidget);
  });

  testWidgets('aucun séparateur sans source unknown', (tester) async {
    await pumpAtWidth(tester, 390);
    expect(find.text('Autres sources'), findsNothing);
  });

  testWidgets('un groupe entièrement unknown reste consultable et séparé', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: PerspectivesInlineSection(
              status: PerspectivesSectionStatus.ready,
              perspectives: [
                _p('Inconnue A', bias: 'unknown'),
                _p('Inconnue B', bias: 'unknown'),
              ],
              coverageCount: 3,
              contentId: 'all-unknown',
              display: DisplayGates.fromCoverageCount(3),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(seconds: 1));

    expect(find.text('Autres sources'), findsOneWidget);
    expect(find.text('?'), findsNothing);
    await tester.scrollUntilVisible(
      find.text('Inconnue B'),
      400,
      scrollable: find.descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      ),
    );
    expect(find.text('Inconnue B'), findsOneWidget);
  });
}
