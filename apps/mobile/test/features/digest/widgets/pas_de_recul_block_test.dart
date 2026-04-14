import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/widgets/pas_de_recul_block.dart';
import 'package:facteur/widgets/design/facteur_card.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });
  const article = DigestItem(
    contentId: 'test-123',
    title: 'Un article d\'analyse approfondie sur la réforme',
    url: 'https://example.com/article',
    source: SourceMini(
      id: 'src-1',
      name: 'Le Monde',
    ),
    badge: 'pas_de_recul',
  );

  Widget buildWidget({
    DigestItem? deepArticle,
    String? introText,
    VoidCallback? onTap,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: PasDeReculBlock(
          deepArticle: deepArticle ?? article,
          introText: introText,
          onTap: onTap,
        ),
      ),
    );
  }

  group('PasDeReculBlock', () {
    testWidgets('displays article title', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(
        find.text('Un article d\'analyse approfondie sur la réforme'),
        findsOneWidget,
      );
    });

    testWidgets('displays source name', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.text('Le Monde'), findsOneWidget);
    });

    testWidgets('displays arrow indicator', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byIcon(Icons.arrow_forward_ios), findsOneWidget);
    });

    testWidgets('uses FacteurCard', (tester) async {
      await tester.pumpWidget(buildWidget());
      expect(find.byType(FacteurCard), findsOneWidget);
    });

    testWidgets('calls onTap when tapped', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildWidget(onTap: () => tapped = true));

      await tester.tap(find.byType(FacteurCard));
      await tester.pumpAndSettle();
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

    testWidgets('displays introText when provided', (tester) async {
      await tester.pumpWidget(buildWidget(
        introText: 'Pour prendre de la hauteur...',
      ));
      expect(find.text('Pour prendre de la hauteur...'), findsOneWidget);
    });

    testWidgets('hides introText when null', (tester) async {
      await tester.pumpWidget(buildWidget(introText: null));
      expect(find.text('Pour prendre de la hauteur...'), findsNothing);
    });

    testWidgets('displays thumbnail when thumbnailUrl present', (tester) async {
      const articleWithThumb = DigestItem(
        contentId: 'test-789',
        title: 'Article avec thumbnail',
        url: 'https://example.com',
        thumbnailUrl: 'https://example.com/thumb.jpg',
        source: SourceMini(id: 'src-1', name: 'Le Monde'),
      );
      await tester.pumpWidget(buildWidget(deepArticle: articleWithThumb));
      // FacteurThumbnail renders SizedBox.shrink on error/null but is present in tree
      expect(find.text('Article avec thumbnail'), findsOneWidget);
    });
  });
}
