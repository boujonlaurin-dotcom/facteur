import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/widgets/pepite_card.dart';

void main() {
  group('PepiteCard', () {
    Source mk({int followers = 42, String? logo}) => Source(
          id: 'src-1',
          name: 'Le Grand Continent',
          type: SourceType.article,
          theme: 'international',
          logoUrl: logo,
          followerCount: followers,
        );

    Widget wrap(Widget child) => ProviderScope(
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: Scaffold(body: Center(child: child)),
          ),
        );

    testWidgets('renders source name and follower count', (tester) async {
      await tester.pumpWidget(wrap(PepiteCard(
        source: mk(followers: 340),
        onToggleFollow: () {},
        onTap: () {},
      )));

      expect(find.text('Le Grand Continent'), findsOneWidget);
      expect(find.textContaining('340'), findsOneWidget);
      expect(find.text('Suivre'), findsOneWidget);
    });

    testWidgets('omits follower count when 0', (tester) async {
      await tester.pumpWidget(wrap(PepiteCard(
        source: mk(followers: 0),
        onToggleFollow: () {},
        onTap: () {},
      )));

      expect(find.textContaining('lecteur'), findsNothing);
    });

    testWidgets('Suivre button fires onToggleFollow', (tester) async {
      var toggled = false;
      var cardTapped = false;

      await tester.pumpWidget(wrap(PepiteCard(
        source: mk(),
        onToggleFollow: () => toggled = true,
        onTap: () => cardTapped = true,
      )));

      await tester.tap(find.text('Suivre'));
      await tester.pump();

      expect(toggled, isTrue);
      expect(cardTapped, isFalse);
    });

    testWidgets('tapping body (not button) fires onTap', (tester) async {
      var toggled = false;
      var cardTapped = false;

      await tester.pumpWidget(wrap(PepiteCard(
        source: mk(),
        onToggleFollow: () => toggled = true,
        onTap: () => cardTapped = true,
      )));

      await tester.tap(find.text('Le Grand Continent'));
      await tester.pump();

      expect(cardTapped, isTrue);
      expect(toggled, isFalse);
    });

    testWidgets('shows Suivi state when isFollowing', (tester) async {
      await tester.pumpWidget(wrap(PepiteCard(
        source: mk(),
        onToggleFollow: () {},
        onTap: () {},
        isFollowing: true,
      )));

      expect(find.text('Suivi'), findsOneWidget);
      expect(find.text('Suivre'), findsNothing);
      // Bouton reste tappable (toggle complet) — onPressed non-null.
      final button =
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.onPressed, isNotNull);
    });
  });
}
