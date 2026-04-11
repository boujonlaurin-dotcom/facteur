import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/widgets/quote_block.dart';

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildWidget({
    required QuoteResponse quote,
    bool dark = false,
  }) {
    return MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: Scaffold(
        body: QuoteBlock(quote: quote),
      ),
    );
  }

  group('QuoteBlock', () {
    testWidgets('displays quote text in rich text', (tester) async {
      const quote = QuoteResponse(
        text: 'La liberté commence où l\'ignorance finit.',
        author: 'Victor Hugo',
      );
      await tester.pumpWidget(buildWidget(quote: quote));
      // Text.rich renders as RichText — find by TextSpan content
      expect(find.byType(RichText), findsWidgets);
      expect(
        find.textContaining('La liberté commence où l\'ignorance finit.'),
        findsOneWidget,
      );
    });

    testWidgets('displays author with em-dash', (tester) async {
      const quote = QuoteResponse(
        text: 'Un texte quelconque.',
        author: 'Albert Camus',
      );
      await tester.pumpWidget(buildWidget(quote: quote));
      expect(find.text('\u2014 Albert Camus'), findsOneWidget);
    });

    testWidgets('returns SizedBox when text is empty', (tester) async {
      const emptyQuote = QuoteResponse(text: '', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: emptyQuote));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('\u2014 Auteur'), findsNothing);
    });

    testWidgets('returns SizedBox when text is only whitespace', (tester) async {
      const blankQuote = QuoteResponse(text: '   ', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: blankQuote));
      expect(find.text('\u2014 Auteur'), findsNothing);
    });

    testWidgets('renders in dark mode without error', (tester) async {
      const quote = QuoteResponse(
        text: 'Il faut imaginer Sisyphe heureux.',
        author: 'Albert Camus',
      );
      await tester.pumpWidget(buildWidget(quote: quote, dark: true));
      expect(
        find.textContaining('Il faut imaginer Sisyphe heureux.'),
        findsOneWidget,
      );
      expect(find.text('\u2014 Albert Camus'), findsOneWidget);
    });

    testWidgets('author text is centered', (tester) async {
      const quote = QuoteResponse(text: 'Texte.', author: 'Auteur centré');
      await tester.pumpWidget(buildWidget(quote: quote));
      final authorFinder = find.text('\u2014 Auteur centré');
      expect(authorFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(authorFinder);
      expect(textWidget.textAlign, TextAlign.center);
    });

    testWidgets('uses compact layout (Column with 3 children)', (tester) async {
      const quote = QuoteResponse(text: 'Texte.', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: quote));
      final column = tester.widget<Column>(
        find.descendant(
          of: find.byType(QuoteBlock),
          matching: find.byType(Column),
        ).first,
      );
      // Text.rich + SizedBox(4) + Author Text = 3
      expect(column.children.length, equals(3));
    });
  });
}
