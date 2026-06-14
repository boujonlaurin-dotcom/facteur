import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/detail/widgets/deep_recommendation_card.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';

void main() {
  DeepRecommendation reco({String matchReason = 'Une analyse de fond.'}) {
    return DeepRecommendation(
      contentId: 'id-1',
      title: 'Le fond du dossier',
      sourceName: 'Le Monde',
      matchReason: matchReason,
    );
  }

  Widget host(Widget child) {
    return MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: Center(child: child)),
    );
  }

  group('DeepRecommendationCard', () {
    testWidgets('affiche kicker, titre, raison et source', (tester) async {
      await tester.pumpWidget(host(DeepRecommendationCard(reco: reco())));
      await tester.pumpAndSettle();

      expect(find.text('PAS DE RECUL'), findsOneWidget);
      expect(find.text('Le fond du dossier'), findsOneWidget);
      expect(find.text('Une analyse de fond.'), findsOneWidget);
      expect(find.text('Le Monde'), findsOneWidget);
    });

    testWidgets('match_reason vide → pas de ligne explicative', (tester) async {
      await tester.pumpWidget(
        host(DeepRecommendationCard(reco: reco(matchReason: '   '))),
      );
      await tester.pumpAndSettle();

      expect(find.text('Le fond du dossier'), findsOneWidget);
      // La seule String secondaire restante est le nom de source.
      expect(find.text('Le Monde'), findsOneWidget);
    });

    testWidgets('tap déclenche onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        host(DeepRecommendationCard(reco: reco(), onTap: () => tapped = true)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Le fond du dossier'));
      await tester.pumpAndSettle();
      expect(tapped, isTrue);
    });
  });
}
