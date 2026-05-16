/// Story 22.1 — tests du picker (4 options visibles, sélection renvoie l'enum).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/widgets/interest_state_picker_sheet.dart';

void main() {
  testWidgets('renders the 4 options', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () => InterestStatePickerSheet.show(
                context,
                title: 'Tech',
                currentState: InterestState.followed,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Favori'), findsOneWidget);
    expect(find.text('Suivi'), findsOneWidget);
    expect(find.text('Neutre'), findsOneWidget);
    expect(find.text('Masqué'), findsOneWidget);
  });

  testWidgets('tap returns the selected state', (tester) async {
    InterestState? returned;
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returned = await InterestStatePickerSheet.show(
                  context,
                  title: 'Tech',
                  currentState: InterestState.unfollowed,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Masqué'));
    await tester.pumpAndSettle();

    expect(returned, InterestState.hidden);
  });

  testWidgets('favorite option disabled when cap reached and not currently favorite',
      (tester) async {
    InterestState? returned;
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () async {
                returned = await InterestStatePickerSheet.show(
                  context,
                  title: 'Sport',
                  currentState: InterestState.followed,
                  favoriteAvailable: false,
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    // Tapping disabled "Favori" should not pop the sheet (InkWell.onTap = null).
    await tester.tap(find.text('Favori'));
    await tester.pump(const Duration(milliseconds: 100));

    expect(returned, isNull);
    // The sheet is still open.
    expect(find.text('Favori'), findsOneWidget);
  });
}
