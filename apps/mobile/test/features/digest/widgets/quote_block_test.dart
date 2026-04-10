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
    testWidgets('displays quote text', (tester) async {
      const quote = QuoteResponse(
        text: 'La liberté commence où l\'ignorance finit.',
        author: 'Victor Hugo',
      );
      await tester.pumpWidget(buildWidget(quote: quote));
      expect(find.text('La liberté commence où l\'ignorance finit.'), findsOneWidget);
    });

    testWidgets('displays author', (tester) async {
      const quote = QuoteResponse(
        text: 'Un texte quelconque.',
        author: 'Albert Camus',
      );
      await tester.pumpWidget(buildWidget(quote: quote));
      expect(find.text('Albert Camus'), findsOneWidget);
    });

    testWidgets('displays decorative guillemet', (tester) async {
      const quote = QuoteResponse(text: 'Texte', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: quote));
      expect(find.text('\u00AB'), findsOneWidget);
    });

    testWidgets('returns SizedBox when text is empty', (tester) async {
      const emptyQuote = QuoteResponse(text: '', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: emptyQuote));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.text('Auteur'), findsNothing);
    });

    testWidgets('returns SizedBox when text is only whitespace', (tester) async {
      const blankQuote = QuoteResponse(text: '   ', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: blankQuote));
      expect(find.text('Auteur'), findsNothing);
    });

    testWidgets('renders in dark mode without error', (tester) async {
      const quote = QuoteResponse(
        text: 'Il faut imaginer Sisyphe heureux.',
        author: 'Albert Camus',
      );
      await tester.pumpWidget(buildWidget(quote: quote, dark: true));
      expect(find.text('Il faut imaginer Sisyphe heureux.'), findsOneWidget);
      expect(find.text('Albert Camus'), findsOneWidget);
    });

    testWidgets('contains a Container with rounded decoration', (tester) async {
      const quote = QuoteResponse(text: 'Texte de test.', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: quote));
      // Should find at least one Container (the outer styled card)
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('renders centered text alignment', (tester) async {
      const quote = QuoteResponse(
        text: 'Une citation bien centrée.',
        author: 'Philosophe',
      );
      await tester.pumpWidget(buildWidget(quote: quote));
      // Find the quote text widget and verify it's centered
      final quoteFinder = find.text('Une citation bien centrée.');
      expect(quoteFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(quoteFinder);
      expect(textWidget.textAlign, TextAlign.center);
    });

    testWidgets('author text is also centered', (tester) async {
      const quote = QuoteResponse(text: 'Texte.', author: 'Auteur centré');
      await tester.pumpWidget(buildWidget(quote: quote));
      final authorFinder = find.text('Auteur centré');
      expect(authorFinder, findsOneWidget);
      final textWidget = tester.widget<Text>(authorFinder);
      expect(textWidget.textAlign, TextAlign.center);
    });

    testWidgets('accent separator line is present', (tester) async {
      const quote = QuoteResponse(text: 'Texte.', author: 'Auteur');
      await tester.pumpWidget(buildWidget(quote: quote));
      // The separator is a Container(width: 32, height: 1.5)
      // We verify the Column has the expected number of children
      final column = tester.widget<Column>(
        find.descendant(
          of: find.byType(QuoteBlock),
          matching: find.byType(Column),
        ).first,
      );
      expect(column.children.length, greaterThanOrEqualTo(4));
    });
  });
}
