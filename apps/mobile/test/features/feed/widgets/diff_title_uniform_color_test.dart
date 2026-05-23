import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/widgets/diff_title.dart';

/// PR 6 — couleur uniforme textPrimary pour tous les chunks non-key.
///
/// Avant : tokens partagés / dimmedFallback étaient rendus en textTertiary,
/// créant une différenciation typographique entre tokens partagés et
/// divergents. PO a demandé : tous les textes des titres en même couleur.
/// Seul le surlignage de fond du key span différencie désormais.
void main() {
  Color primary() =>
      FacteurTheme.lightTheme.extension<FacteurColors>()!.textPrimary;
  Color tertiary() =>
      FacteurTheme.lightTheme.extension<FacteurColors>()!.textTertiary;

  Widget host(DiffTitle child) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  List<TextSpan> collectTextSpans(WidgetTester tester) {
    final spans = <TextSpan>[];
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      rt.text.visitChildren((span) {
        if (span is TextSpan && (span.text?.isNotEmpty ?? false)) {
          spans.add(span);
        }
        return true;
      });
    }
    return spans;
  }

  group('DiffTitle — uniform textPrimary color', () {
    testWidgets('Mode 3 (key + shared) : tous les TextSpan en textPrimary',
        (tester) async {
      await tester.pumpWidget(host(DiffTitle(
        title: 'Macron annonce une réforme',
        highlightSpans: const [
          HighlightSpan(start: 7, end: 14, text: 'annonce', bias: 'right'),
        ],
        sharedTokens: const [
          TokenSpan(start: 0, end: 6, text: 'Macron'),
          TokenSpan(start: 19, end: 26, text: 'réforme'),
        ],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      await tester.pumpAndSettle();

      final spans = collectTextSpans(tester);
      expect(spans, isNotEmpty);
      for (final s in spans) {
        // Le key span est rendu via WidgetSpan → texte enfant Text — récupéré
        // aussi par visitChildren et doit également être textPrimary.
        expect(s.style?.color, primary(),
            reason: 'Tous les TextSpan doivent être en textPrimary, vu: '
                '${s.text} → ${s.style?.color}');
        expect(s.style?.color, isNot(tertiary()));
      }
    });

    testWidgets('Mode 2 (sans shared) : pas de textTertiary sur le hors-key',
        (tester) async {
      await tester.pumpWidget(host(DiffTitle(
        title: 'Tsahal frappe Gaza',
        highlightSpans: const [
          HighlightSpan(start: 7, end: 13, text: 'frappe', bias: 'left'),
        ],
        sharedTokens: const [],
        biasColor: Colors.blue,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      await tester.pumpAndSettle();

      final spans = collectTextSpans(tester);
      expect(spans, isNotEmpty);
      for (final s in spans) {
        expect(s.style?.color, primary(),
            reason: 'Mode 2 : hors-key doit être en textPrimary, pas tertiary');
        expect(s.style?.color, isNot(tertiary()));
      }
    });

    testWidgets('Mode shared en cours d\'animation : reste en textPrimary',
        (tester) async {
      // Avant PR 6 : la couleur des shared chunks était interpolée entre
      // textPrimary et textTertiary par Color.lerp pendant la cascade. PR 6 :
      // plus d'interpolation, couleur constante textPrimary à tous les frames.
      await tester.pumpWidget(host(DiffTitle(
        title: 'Macron annonce',
        highlightSpans: const [
          HighlightSpan(start: 7, end: 14, text: 'annonce', bias: 'right'),
        ],
        sharedTokens: const [TokenSpan(start: 0, end: 6, text: 'Macron')],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: true,
      )));
      // Pump à mi-animation
      await tester.pump(const Duration(milliseconds: 380));
      final spans = collectTextSpans(tester);
      for (final s in spans) {
        expect(s.style?.color, primary(),
            reason:
                'À tous les frames de la cascade, les TextSpan doivent rester '
                'en textPrimary (plus d\'interpolation Color.lerp).');
      }
      await tester.pumpAndSettle(const Duration(seconds: 2));
    });
  });
}
