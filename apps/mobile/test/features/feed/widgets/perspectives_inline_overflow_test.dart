import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/coverage_spectrum_bar.dart';

void main() {
  testWidgets('cm-panel-inline Row : aucun overflow en viewport 390px',
      (tester) async {
    tester.view.physicalSize = const Size(390 * 3, 844 * 3);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SizedBox(
          width: 390,
          child: Container(
            decoration: BoxDecoration(
              border: Border(
                top: BorderSide(
                    color: Colors.black.withValues(alpha: 0.08), width: 1),
                bottom: BorderSide(
                    color: Colors.black.withValues(alpha: 0.08), width: 1),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Text(
                    'Couverture médiatique (5)',
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                    style: GoogleFonts.dmSans(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      letterSpacing: -0.1,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                const CoverageSpectrumBar(distribution: {
                  'left': 1,
                  'center-left': 1,
                  'center': 1,
                  'center-right': 1,
                  'right': 1,
                }),
                const SizedBox(width: 10),
                Icon(PhosphorIcons.caretDown(PhosphorIconsStyle.regular),
                    size: 14),
              ],
            ),
          ),
        ),
      ),
    ));

    final exception = tester.takeException();
    expect(exception, isNull,
        reason:
            'Le Row du bandeau cm-panel-inline ne doit pas déborder en 390px '
            '(exception capturée : $exception)');
  });
}
