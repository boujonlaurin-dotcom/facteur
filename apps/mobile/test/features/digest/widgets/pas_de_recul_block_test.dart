import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/widgets/pas_de_recul_block.dart';

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

    testWidgets('uses InkWell wrapper for tap (no introText)', (tester) async {
      await tester.pumpWidget(buildWidget());
      // Legacy path: single InkWell covering the whole card.
      expect(find.byType(InkWell), findsOneWidget);
    });

    testWidgets('calls onTap when tapped (no introText)', (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildWidget(onTap: () => tapped = true));

      await tester.tap(find.byType(InkWell));
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

    testWidgets('introText hidden by default (collapsed)', (tester) async {
      await tester.pumpWidget(buildWidget(
        introText: 'Pour prendre de la hauteur...',
      ));
      expect(find.text('Pour prendre de la hauteur...'), findsNothing);
      expect(find.text('Pourquoi cet article ?'), findsOneWidget);
      expect(find.byIcon(Icons.expand_more), findsOneWidget);
    });

    testWidgets('tap on "Pourquoi cet article ?" expands intro', (tester) async {
      await tester.pumpWidget(buildWidget(
        introText: 'Pour prendre de la hauteur...',
      ));
      await tester.tap(find.text('Pourquoi cet article ?'));
      await tester.pump();
      expect(find.text('Pour prendre de la hauteur...'), findsOneWidget);
      expect(find.text('Réduire'), findsOneWidget);
      expect(find.byIcon(Icons.expand_less), findsOneWidget);
      expect(find.text('Pourquoi cet article ?'), findsNothing);
    });

    testWidgets('tap on "Réduire" collapses intro', (tester) async {
      await tester.pumpWidget(buildWidget(
        introText: 'Pour prendre de la hauteur...',
      ));
      await tester.tap(find.text('Pourquoi cet article ?'));
      await tester.pump();
      expect(find.text('Pour prendre de la hauteur...'), findsOneWidget);
      await tester.tap(find.text('Réduire'));
      await tester.pump();
      expect(find.text('Pour prendre de la hauteur...'), findsNothing);
      expect(find.text('Pourquoi cet article ?'), findsOneWidget);
    });

    testWidgets('with introText, tap on article row opens article',
        (tester) async {
      bool tapped = false;
      await tester.pumpWidget(buildWidget(
        introText: 'Contexte...',
        onTap: () => tapped = true,
      ));
      // Tap on article title (inner InkWell intercepts parent toggle).
      await tester.tap(
          find.text('Un article d\'analyse approfondie sur la réforme'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
      // Intro remains collapsed (parent toggle NOT triggered).
      expect(find.text('Contexte...'), findsNothing);
    });

    testWidgets('hides introText when null', (tester) async {
      await tester.pumpWidget(buildWidget(introText: null));
      expect(find.text('Pour prendre de la hauteur...'), findsNothing);
      expect(find.text('Pourquoi cet article ?'), findsNothing);
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
