import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/widgets/disambiguation_suggestion_tile.dart';

const _suggestion = DisambiguationSuggestion(
  canonicalName: 'Donald Trump',
  entityType: 'PERSON',
  description: 'Président des États-Unis',
  slugParent: 'politics',
);

Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(body: child),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('renders canonical name, type label and a Suivre button',
      (tester) async {
    await tester.pumpWidget(_wrap(
      DisambiguationSuggestionTile(
        suggestion: _suggestion,
        isFollowing: false,
        onFollow: () {},
      ),
    ));

    expect(find.text('Donald Trump'), findsOneWidget);
    expect(find.text('Suivre'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('tapping Suivre fires onFollow', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_wrap(
      DisambiguationSuggestionTile(
        suggestion: _suggestion,
        isFollowing: false,
        onFollow: () => tapped = true,
      ),
    ));

    await tester.tap(find.text('Suivre'));
    expect(tapped, isTrue);
  });

  testWidgets('shows a spinner instead of the button while following',
      (tester) async {
    await tester.pumpWidget(_wrap(
      DisambiguationSuggestionTile(
        suggestion: _suggestion,
        isFollowing: true,
        onFollow: null,
      ),
    ));

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Suivre'), findsNothing);
  });

  testWidgets('null onFollow disables the button', (tester) async {
    await tester.pumpWidget(_wrap(
      const DisambiguationSuggestionTile(
        suggestion: _suggestion,
        isFollowing: false,
        onFollow: null,
      ),
    ));

    final button = tester.widget<TextButton>(find.byType(TextButton));
    expect(button.onPressed, isNull);
  });
}
