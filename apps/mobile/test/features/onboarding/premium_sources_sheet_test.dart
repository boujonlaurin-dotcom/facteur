import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/onboarding/widgets/premium_sources_sheet.dart';
import 'package:facteur/features/sources/models/source_model.dart';

Source _source(
  String id,
  String name, {
  bool isCurated = true,
  bool hasSubscription = false,
}) {
  return Source(
    id: id,
    name: name,
    type: SourceType.article,
    isCurated: isCurated,
    hasSubscription: hasSubscription,
  );
}

Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets(
    'liste = sources validées (sélection) — pas le gating premiumConnection',
    (tester) async {
      final sources = [
        _source('a', 'Le Monde'), // validée
        _source('b', 'Mediapart'), // non validée
        _source('c', 'Source non curée', isCurated: false),
      ];

      await tester.pumpWidget(_wrap(
        PremiumSourcesSheet(
          allSources: sources,
          selectedSourceIds: const {'a'},
        ),
      ));
      await tester.pumpAndSettle();

      // Seule la source validée et curée est affichée.
      expect(find.text('Le Monde'), findsOneWidget);
      expect(find.text('Mediapart'), findsNothing);
      expect(find.text('Source non curée'), findsNothing);
    },
  );

  testWidgets('pré-coche les abonnements déjà connus (hasSubscription)',
      (tester) async {
    final sources = [
      _source('a', 'Le Monde', hasSubscription: true),
    ];

    await tester.pumpWidget(_wrap(
      PremiumSourcesSheet(
        allSources: sources,
        // Source absente de la sélection mais déjà abonnée → affichée + cochée.
        selectedSourceIds: const {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Le Monde'), findsOneWidget);
    // Un abonnement déjà connu propose de se « Dissocier ».
    expect(find.text('Dissocier'), findsOneWidget);
    expect(find.text('Connecter'), findsNothing);
  });

  testWidgets('aucune source validée → message d\'état vide adapté',
      (tester) async {
    await tester.pumpWidget(_wrap(
      PremiumSourcesSheet(
        allSources: [_source('a', 'Le Monde')],
        selectedSourceIds: const {},
      ),
    ));
    await tester.pumpAndSettle();

    expect(
      find.text("Vous n'avez pas encore validé de source."),
      findsOneWidget,
    );
  });
}
