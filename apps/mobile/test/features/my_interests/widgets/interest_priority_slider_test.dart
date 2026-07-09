/// Tests du curseur 4-états partagé (thèmes / sujets + fiche source).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/widgets/interest_priority_slider.dart';
import 'package:facteur/features/my_interests/widgets/interest_state_picker_sheet.dart';

Widget _host(Widget child) => MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );

void main() {
  testWidgets('renders the 4 state labels + current description',
      (tester) async {
    await tester.pumpWidget(
      _host(
        InterestPrioritySlider(
          value: InterestState.followed,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Favori'), findsOneWidget);
    expect(find.text('Suivi'), findsOneWidget);
    expect(find.text('Neutre'), findsOneWidget);
    expect(find.text('Masqué'), findsOneWidget);
    // Description du cran courant (followed).
    expect(find.text('Présent dans votre flux'), findsOneWidget);
  });

  testWidgets('dragging the thumb reports the new state on drag end',
      (tester) async {
    InterestState? reported;
    await tester.pumpWidget(
      _host(
        InterestPrioritySlider(
          value: InterestState.unfollowed,
          onChanged: (s) => reported = s,
        ),
      ),
    );

    // Glisse le thumb vers la droite (au-delà du dernier cran) → Favori.
    await tester.drag(find.byType(Slider), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(reported, InterestState.favorite);
  });

  testWidgets('does not report when the state is unchanged', (tester) async {
    var callCount = 0;
    await tester.pumpWidget(
      _host(
        InterestPrioritySlider(
          value: InterestState.favorite,
          onChanged: (_) => callCount++,
        ),
      ),
    );

    // Drag vers la droite alors qu'on est déjà au cran max (favorite).
    await tester.drag(find.byType(Slider), const Offset(500, 0));
    await tester.pumpAndSettle();

    expect(callCount, 0);
  });

  testWidgets('pinnedTopic semantics renders "Épinglé" instead of "Favori"',
      (tester) async {
    await tester.pumpWidget(
      _host(
        InterestPrioritySlider(
          value: InterestState.favorite,
          favoriteSemantics: FavoriteSemantics.pinnedTopic,
          onChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Épinglé'), findsOneWidget);
    expect(find.text('Favori'), findsNothing);
    expect(
      find.textContaining('onglet dans la section Flâner'),
      findsOneWidget,
    );
  });
}
