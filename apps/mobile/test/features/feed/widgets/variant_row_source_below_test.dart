import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show HighlightSpan, TokenSpan;
import 'package:facteur/features/feed/widgets/diff_title.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

/// PR 6 — feedback PO : dans le mode inline (_VariantRow), la head row
/// (favicon + source + bias label + arrow) doit passer SOUS le DiffTitle.
/// Vérifie l'ordre vertical via les positions absolues des deux widgets.
Perspective _persp(String name, String bias) => Perspective(
      title: 'Titre court avec mot fort',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: bias,
      highlightSpans: const [
        HighlightSpan(start: 18, end: 22, text: 'fort', bias: 'left'),
      ],
      sharedTokens: const [TokenSpan(start: 0, end: 5, text: 'Titre')],
    );

Widget _harness() {
  return ProviderScope(
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SingleChildScrollView(
          child: SizedBox(
            width: 390,
            child: PerspectivesInlineSection(
              perspectives: [
                _persp('Source-Gauche', 'left'),
                _persp('Source-Droite', 'right'),
              ],
              biasDistribution: const {'left': 1, 'right': 1},
              keywords: const [],
              contentId: 'test',
              externalSelectedSegments: null,
              onSegmentTap: (_) {},
              onClearSegments: () {},
              onToggle: () {},
              isExpanded: true,
              referenceTitle: '',
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets(
      '_VariantRow : DiffTitle est placé AU-DESSUS de la head row (favicon + arrow)',
      (tester) async {
    await tester.pumpWidget(_harness());
    await tester.pumpAndSettle(const Duration(seconds: 2));

    final diffTitles = find.byType(DiffTitle);
    expect(diffTitles, findsWidgets,
        reason: 'Au moins un DiffTitle doit être présent dans les variants.');

    // L'icône arrowUpRight ne se trouve que dans la head row du _VariantRow.
    final arrowIcons = find.byWidgetPredicate((w) =>
        w is Icon &&
        w.icon == PhosphorIcons.arrowUpRight(PhosphorIconsStyle.regular));
    expect(arrowIcons, findsWidgets,
        reason:
            'L\'icône arrow-up-right est l\'ancre de la head row dans _VariantRow.');

    // Compare la position verticale du premier DiffTitle vs le premier arrow :
    // après PR 6, le DiffTitle doit être au-dessus (dy plus petit).
    final firstDiffTitleY = tester.getTopLeft(diffTitles.first).dy;
    final firstArrowY = tester.getTopLeft(arrowIcons.first).dy;

    expect(firstDiffTitleY, lessThan(firstArrowY),
        reason:
            'Le DiffTitle doit être placé AU-DESSUS de la head row (favicon + '
            'source + arrow). Position DiffTitle.dy=$firstDiffTitleY doit être '
            '< position arrow.dy=$firstArrowY.');
  });
}
