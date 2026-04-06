import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/widgets/pas_de_recul_block.dart';

void main() {
  const article = DigestItem(
    contentId: 'test-123',
    title: 'Un article d\'analyse approfondie sur la r\u00e9forme',
    url: 'https://example.com/article',
    source: const SourceMini(
      id: 'src-1',
      name: 'Le Monde',
    ),
    badge: 'pas_de_recul',
  );

  Widget buildWidget({
    DigestItem? deepArticle,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PasDeReculBlock(
          deepArticle: deepArticle ?? article,
          onTap: onTap,
        ),
      ),
    );
  }

  group('PasDeReculBlock', () {
    testWidgets('displays article title', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(
        find.text('Un article d\'analyse approfondie sur la r\u00e9forme'),
        findsOneWidget,
      );
    });

    testWidgets('displays source name', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Le Monde'), findsOneWidget);
    });

    testWidgets('displays "Lire" CTA', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Lire \u2192'), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildWidget(onTap: () => tapped = true));

      await tester.tap(find.byType(PasDeReculBlock));
      expect(tapped, isTrue);
    });

    testWidgets('handles article without source', (tester) async {
      const noSourceArticle = DigestItem(
        contentId: 'test-456',
        title: 'Article sans source',
        url: 'https://example.com',
      );
      await tester.pumpWidget(buildWidget(deepArticle: noSourceArticle));
      expect(find.text('Article sans source'), findsOneWidget);
      expect(find.text('Le Monde'), findsNothing);
    });
  });
}
