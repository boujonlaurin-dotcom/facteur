import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
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
                biasDistribution: const {
                  'left': 1,
                  'center-left': 1,
                  'center': 1,
                  'center-right': 1,
                  'right': 1,
                },
                contentId: 'test',
                divergenceLevel: 'medium',
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
        find.text('Couverture médiatique (5)'),
      );
      expect(titleRender.didExceedMaxLines, isFalse);

      final spectrumSize = tester.getSize(find.byType(CoverageSpectrumBar));
      expect(spectrumSize.width, lessThanOrEqualTo(96));
    });
  }
}
