import 'package:facteur/config/theme.dart';
import 'package:facteur/features/detail/widgets/article_tags_row.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget subject({double width = 220}) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(
        body: SizedBox(
          width: width,
          child: ArticleTagsRow(
            items: [
              ArticleTagItem(label: 'Technologie', onTap: () {}),
              ArticleTagItem(label: 'Intelligence artificielle', onTap: () {}),
              ArticleTagItem(label: 'OpenAI', onTap: () {}),
              ArticleTagItem(label: 'Europe', onTap: () {}),
            ],
            onOverflowTap: () {},
          ),
        ),
      ),
    );
  }

  testWidgets('does not render the partial-content badge', (tester) async {
    await tester.pumpWidget(subject());

    expect(find.text('Aperçu — contenu partiel'), findsNothing);
  });

  testWidgets('keeps tags on one line and shows an overflow chip', (
    tester,
  ) async {
    await tester.pumpWidget(subject(width: 220));

    final visibleTexts = find.descendant(
      of: find.byType(ArticleTagsRow),
      matching: find.byType(Text),
    );
    final yPositions = tester
        .widgetList<Text>(visibleTexts)
        .map((text) => tester.getTopLeft(find.text(text.data!)).dy)
        .toSet();

    expect(yPositions, hasLength(1));
    expect(find.textContaining(RegExp(r'^\+\d+ sujets?$')), findsOneWidget);
  });
}
