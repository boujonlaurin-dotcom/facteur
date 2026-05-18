import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/widgets/diff_title.dart';

void main() {
  Widget host(DiffTitle child) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  Iterable<String> _richTextStrings(WidgetTester tester) sync* {
    for (final rt in tester.widgetList<RichText>(find.byType(RichText))) {
      final out = StringBuffer();
      rt.text.visitChildren((span) {
        if (span is TextSpan && span.text != null) out.write(span.text);
        return true;
      });
      final s = out.toString();
      if (s.isNotEmpty) yield s;
    }
  }

  group('DiffTitle', () {
    testWidgets('reconstitue le titre original en Mode 3 (key + shared)',
        (tester) async {
      // "Macron annonce une réforme" — pos 0-6 Macron (shared),
      // 7-14 annonce (key), 19-26 réforme (shared).
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

      final combined = _richTextStrings(tester).join();
      expect(combined.contains('Macron'), isTrue);
      expect(combined.contains('annonce'), isTrue);
      expect(combined.contains('réforme'), isTrue);
    });

    testWidgets('fallback Mode 2 : sans sharedTokens → hors-key en tertiary',
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

      // Mode 2 : le titre est toujours reconstruit, et le hors-key (Tsahal,
      // Gaza) doit être en text_tertiary. On vérifie au moins que le widget
      // a bien un wash (Container) pour le key span.
      expect(find.byType(Container), findsWidgets);
      final combined = _richTextStrings(tester).join();
      expect(combined.contains('Tsahal'), isTrue);
      expect(combined.contains('Gaza'), isTrue);
    });

    testWidgets('animateIn=false → état final immédiat (controller value=1)',
        (tester) async {
      await tester.pumpWidget(host(DiffTitle(
        title: 'Macron',
        highlightSpans: const [
          HighlightSpan(start: 0, end: 6, text: 'Macron', bias: 'left'),
        ],
        sharedTokens: const [],
        biasColor: Colors.green,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      // Un seul pump suffit — animation déjà finie.
      await tester.pump();

      // Pas de Future.delayed lancé → on ne devrait pas avoir de timers
      // pendants. Si Tester se plaint à pumpAndSettle c'est qu'on a une
      // fuite.
      await tester.pumpAndSettle();
    });

    testWidgets('animateIn=true → AnimationController démarre après délai',
        (tester) async {
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
      await tester.pump(); // build initial
      // À ce stade, l'animation n'a pas commencé (Future.delayed 80 ms).
      // On avance le temps au-delà du délai + durée totale.
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      // Titre toujours présent après animation.
      final combined = _richTextStrings(tester).join();
      expect(combined.contains('Macron'), isTrue);
      expect(combined.contains('annonce'), isTrue);
    });

    testWidgets(
        'titre sans aucun span → rendu plain en textPrimary (pas dimmedFallback)',
        (tester) async {
      // Regression Bug Couverture #1 : quand le back renvoie highlight_spans=[]
      // ET shared_tokens=[] (ex. article sans cluster_id), DiffTitle ne doit
      // PAS dimmer le titre entier en textTertiary — il doit rester en
      // textPrimary, comme un titre standard sans diff.
      await tester.pumpWidget(host(DiffTitle(
        title: 'Aucune divergence détectée',
        highlightSpans: const [],
        sharedTokens: const [],
        biasColor: Colors.red,
        baseStyle: const TextStyle(fontSize: 14),
        animateIn: false,
      )));
      await tester.pumpAndSettle();

      final richText = tester.widget<RichText>(find.byType(RichText));
      final root = richText.text as TextSpan;
      expect(root.children, isNotNull);
      expect(root.children!.length, 1,
          reason: 'Un unique chunk plain attendu');
      final only = root.children!.first as TextSpan;
      expect(only.text, 'Aucune divergence détectée');

      final expectedPrimary =
          FacteurTheme.lightTheme.extension<FacteurColors>()!.textPrimary;
      final expectedTertiary =
          FacteurTheme.lightTheme.extension<FacteurColors>()!.textTertiary;
      expect(only.style?.color, expectedPrimary,
          reason: 'Le chunk doit être en textPrimary, pas dimmedFallback');
      expect(only.style?.color, isNot(expectedTertiary));
    });
  });
}
