import 'package:facteur/config/theme.dart';
import 'package:facteur/features/detail/widgets/article_reader_widget.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: FacteurTheme.lightTheme,
    home: Scaffold(body: child),
  );
}

void main() {
  group('ArticleReaderWidget footer spacing', () {
    testWidgets('uses the default spacer before the footer', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ArticleReaderWidget(
            title: 'Titre',
            description: 'Description courte.',
            footer: Text('Footer'),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.height == FacteurSpacing.space8,
        ),
        findsOneWidget,
      );
      expect(find.text('Footer'), findsOneWidget);
    });

    testWidgets('can remove the spacer before the footer', (tester) async {
      await tester.pumpWidget(
        _wrap(
          const ArticleReaderWidget(
            title: 'Titre',
            description: 'Description courte.',
            footerSpacing: 0,
            footer: Text('Footer'),
          ),
        ),
      );

      expect(
        find.byWidgetPredicate(
          (widget) =>
              widget is SizedBox && widget.height == FacteurSpacing.space8,
        ),
        findsNothing,
      );
      expect(find.text('Footer'), findsOneWidget);
    });
  });
}
