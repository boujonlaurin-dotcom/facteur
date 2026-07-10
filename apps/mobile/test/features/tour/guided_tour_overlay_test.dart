import 'package:facteur/config/theme.dart';
import 'package:facteur/features/tour/models/tour_step.dart';
import 'package:facteur/features/tour/tour_strings.dart';
import 'package:facteur/features/tour/widgets/guided_tour_coach_card.dart';
import 'package:facteur/features/tour/widgets/guided_tour_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: child),
    );

void main() {
  testWidgets('coach card affiche titre, pastille et puces', (tester) async {
    await tester.pumpWidget(
      _host(
        GuidedTourCoachCard(
          step: TourStep.essentielHero,
          onSkip: () {},
          onNext: () {},
        ),
      ),
    );

    expect(find.text(TourStrings.title(TourStep.essentielHero)), findsOneWidget);
    expect(find.text('1 / 5'), findsOneWidget);
    expect(find.text(TourStrings.next), findsOneWidget);
    expect(find.text(TourStrings.skip), findsOneWidget);
  });

  testWidgets('« Suivant » et « Passer » remontent leurs callbacks',
      (tester) async {
    var next = 0;
    var skip = 0;
    await tester.pumpWidget(
      _host(
        GuidedTourCoachCard(
          step: TourStep.descendsCartes,
          onSkip: () => skip++,
          onNext: () => next++,
        ),
      ),
    );

    await tester.tap(find.text(TourStrings.next));
    await tester.tap(find.text(TourStrings.skip));
    await tester.pump();

    expect(next, 1);
    expect(skip, 1);
  });

  testWidgets('dernière étape affiche « Terminer »', (tester) async {
    await tester.pumpWidget(
      _host(
        GuidedTourCoachCard(
          step: TourStep.courrier,
          onSkip: () {},
          onNext: () {},
        ),
      ),
    );
    expect(find.text(TourStrings.finish), findsOneWidget);
    expect(find.text('5 / 5'), findsOneWidget);
  });

  testWidgets('carte de conclusion masque puces et boutons', (tester) async {
    await tester.pumpWidget(
      _host(
        GuidedTourCoachCard(
          step: TourStep.done,
          onSkip: () {},
          onNext: () {},
        ),
      ),
    );
    expect(find.text(TourStrings.title(TourStep.done)), findsOneWidget);
    expect(find.text(TourStrings.next), findsNothing);
    expect(find.text(TourStrings.finish), findsNothing);
    expect(find.text(TourStrings.skip), findsNothing);
  });

  testWidgets('overlay sans ancre (Flâner) rend un voile plein sans crash',
      (tester) async {
    // NB : ticker en `repeat()` → JAMAIS de pumpAndSettle (ne se stabilise pas).
    await tester.pumpWidget(
      _host(
        GuidedTourOverlay(
          step: TourStep.flaner,
          targets: const [],
          centerCard: true,
          onSkip: () {},
          onNext: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text(TourStrings.title(TourStep.flaner)), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
