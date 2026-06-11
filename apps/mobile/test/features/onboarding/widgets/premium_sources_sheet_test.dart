import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/onboarding/widgets/premium_sources_sheet.dart';
import 'package:facteur/features/sources/models/source_model.dart';

/// Item 4 du plan « Ajustements onboarding » : le CTA d'abonnement ne s'affiche
/// que pour les sources payantes, avec « Connecter » (config curée) vs
/// « Associer » (fallback générique). Les sources gratuites montrent « Suivie ✓ »
/// sans CTA (donc plus de bouton no-op).
Source _source({
  required String id,
  required String name,
  required bool hasPaywall,
  String? url,
  PremiumConnection? premiumConnection,
}) {
  return Source(
    id: id,
    name: name,
    type: SourceType.article,
    url: url,
    isCurated: true,
    hasPaywall: hasPaywall,
    premiumConnection: premiumConnection,
  );
}

void main() {
  Future<void> pumpSheet(WidgetTester tester, List<Source> sources) async {
    await tester.pumpWidget(
      ProviderScope(
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: PremiumSourcesSheet(
              allSources: sources,
              selectedSourceIds: sources.map((s) => s.id).toSet(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('source gratuite : « Suivie », aucun CTA de connexion',
      (tester) async {
    await pumpSheet(tester, [
      _source(
        id: 'free1',
        name: 'Source Gratuite',
        hasPaywall: false,
        url: 'https://gratuit.example',
      ),
    ]);

    expect(find.text('Suivie'), findsOneWidget);
    expect(find.text('Connecter'), findsNothing);
    expect(find.text('Associer'), findsNothing);
  });

  testWidgets(
      'source payante sans config premium : fallback générique « Associer »',
      (tester) async {
    await pumpSheet(tester, [
      _source(
        id: 'paid1',
        name: 'Media Payant',
        hasPaywall: true,
        url: 'https://payant.example',
        premiumConnection: null,
      ),
    ]);

    // Plus de no-op : le bouton existe, labellé « Associer » (générique).
    expect(find.text('Associer'), findsOneWidget);
    expect(find.text('Connecter'), findsNothing);
    expect(find.text('Suivie'), findsNothing);
  });

  testWidgets('source payante avec config curée : « Connecter »',
      (tester) async {
    await pumpSheet(tester, [
      _source(
        id: 'paid2',
        name: 'Media Cure',
        hasPaywall: true,
        url: 'https://cure.example',
        premiumConnection: const PremiumConnection(
          loginUrl: 'https://cure.example/login',
          testUrl: 'https://cure.example/article',
        ),
      ),
    ]);

    expect(find.text('Connecter'), findsOneWidget);
    expect(find.text('Associer'), findsNothing);
  });

  testWidgets(
      'source payante sans URL valide : pas de CTA générique (« Suivie »)',
      (tester) async {
    await pumpSheet(tester, [
      _source(
        id: 'paid3',
        name: 'Payant Sans Url',
        hasPaywall: true,
        url: null,
        premiumConnection: null,
      ),
    ]);

    expect(find.text('Suivie'), findsOneWidget);
    expect(find.text('Associer'), findsNothing);
    expect(find.text('Connecter'), findsNothing);
  });
}
