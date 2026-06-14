import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
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
  testWidgets('header 2 lignes + carrousel : aucun overflow en viewport 390px',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: SizedBox(
              width: 390,
              child: PerspectivesInlineSection(
                status: PerspectivesSectionStatus.ready,
                perspectives: [
                  _p('Libération', bias: 'left'),
                  _p('France 24', bias: 'center-left'),
                  _p('Les Échos', bias: 'center-right'),
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

    final exception = tester.takeException();
    expect(
      exception,
      isNull,
      reason: 'Le header 2 lignes + carrousel ne doit pas déborder en 390px '
          '(exception capturée : $exception)',
    );
  });
}
