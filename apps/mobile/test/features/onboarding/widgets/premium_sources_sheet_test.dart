import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/onboarding/widgets/premium_sources_sheet.dart';
import 'package:facteur/features/sources/models/source_model.dart';

/// The onboarding CTA is available for every backend-connectable HTTP source,
/// not only sources marked as paywalled.
Source _source({
  required String id,
  required String name,
  required bool hasPaywall,
  String? url,
  bool canConnectLogin = true,
  PremiumConnection? premiumConnection,
}) {
  return Source(
    id: id,
    name: name,
    type: SourceType.article,
    url: url,
    isCurated: true,
    hasPaywall: hasPaywall,
    canConnectLogin: canConnectLogin,
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

  testWidgets('source HTTP sans paywall : « Connecter »', (tester) async {
    await pumpSheet(tester, [
      _source(
        id: 'free1',
        name: 'Source Gratuite',
        hasPaywall: false,
        url: 'https://gratuit.example',
      ),
    ]);

    expect(find.text('Connecter'), findsOneWidget);
    expect(find.text('Suivie'), findsNothing);
    expect(find.text('Associer'), findsNothing);
  });

  testWidgets(
    'source payante sans config premium : fallback générique « Connecter »',
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

      expect(find.text('Connecter'), findsOneWidget);
      expect(find.text('Associer'), findsNothing);
      expect(find.text('Suivie'), findsNothing);
    },
  );

  testWidgets('source payante avec config curée : « Connecter »', (
    tester,
  ) async {
    await pumpSheet(tester, [
      _source(
        id: 'paid2',
        name: 'Media Cure',
        hasPaywall: true,
        url: 'https://cure.example',
        canConnectLogin: true,
        premiumConnection: const PremiumConnection(
          loginUrl: 'https://cure.example/login',
          testUrl: 'https://cure.example/article',
        ),
      ),
    ]);

    expect(find.text('Connecter'), findsOneWidget);
    expect(find.text('Associer'), findsNothing);
  });

  testWidgets('source explicitement non connectable : « Suivie »', (
    tester,
  ) async {
    await pumpSheet(tester, [
      _source(
        id: 'paid3',
        name: 'Payant Sans Url',
        hasPaywall: true,
        url: 'https://incompatible.example',
        canConnectLogin: false,
        premiumConnection: null,
      ),
    ]);

    expect(find.text('Suivie'), findsOneWidget);
    expect(find.text('Associer'), findsNothing);
    expect(find.text('Connecter'), findsNothing);
  });

  testWidgets('source sans URL valide : « Suivie »', (tester) async {
    await pumpSheet(tester, [
      _source(
        id: 'missing-url',
        name: 'Sans URL',
        hasPaywall: false,
        url: null,
        canConnectLogin: false,
      ),
    ]);

    expect(find.text('Suivie'), findsOneWidget);
    expect(find.text('Connecter'), findsNothing);
  });
}
