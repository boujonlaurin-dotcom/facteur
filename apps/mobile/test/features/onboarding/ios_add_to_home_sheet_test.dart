import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge_coordinator.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/onboarding/providers/ios_add_to_home_provider.dart';
import 'package:facteur/features/onboarding/widgets/ios_add_to_home_sheet.dart';

class _NoopAnalytics implements AnalyticsService {
  @override
  dynamic noSuchMethod(Invocation invocation) async {}
}

Widget _wrap({required List<Override> overrides, required Widget child}) {
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
      ...overrides,
    ],
    child: MaterialApp(home: Scaffold(body: child)),
  );
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('rend le titre, les 3 étapes et les deux CTAs', (tester) async {
    await tester.pumpWidget(_wrap(
      overrides: const [],
      child: const IosAddToHomeSheet(),
    ));
    await tester.pump();

    expect(find.text('Gardez Facteur à portée de main'), findsOneWidget);
    expect(find.textContaining("Touchez l'icône Partage"), findsOneWidget);
    expect(find.textContaining("Sur l'écran d'accueil"), findsOneWidget);
    expect(find.textContaining('Confirmez avec "Ajouter"'), findsOneWidget);
    expect(find.text("C'est fait"), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
  });

  testWidgets('tap "C\'est fait" marque le nudge comme vu (permanent)',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = NudgeStorage(prefs: prefs);
    final service = NudgeService(storage: storage);

    await tester.pumpWidget(_wrap(
      overrides: [
        nudgeServiceProvider.overrideWithValue(service),
      ],
      child: const IosAddToHomeSheet(),
    ));
    await tester.pump();

    await tester.ensureVisible(find.text("C'est fait"));
    await tester.tap(find.text("C'est fait"));
    await tester.pumpAndSettle();

    expect(await service.isSeen(NudgeIds.iosAddToHome), isTrue);
  });

  testWidgets('tap "Plus tard" enregistre `lastShown` (snooze 7j)',
      (tester) async {
    final prefs = await SharedPreferences.getInstance();
    final storage = NudgeStorage(prefs: prefs);
    final service = NudgeService(storage: storage);

    await tester.pumpWidget(_wrap(
      overrides: [
        nudgeServiceProvider.overrideWithValue(service),
      ],
      child: const IosAddToHomeSheet(),
    ));
    await tester.pump();

    await tester.ensureVisible(find.text('Plus tard'));
    await tester.tap(find.text('Plus tard'));
    await tester.pumpAndSettle();

    expect(await service.isSeen(NudgeIds.iosAddToHome), isFalse);
    expect(await service.lastShown(NudgeIds.iosAddToHome), isNotNull);
  });

  test('controller.shouldShow=false hors web (stub)', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = NudgeService(storage: NudgeStorage(prefs: prefs));
    final controller = IosAddToHomeController(nudgeService: service);
    // En contexte de test (non-web), isIosSafariNonStandalone()=false
    // donc shouldShow doit court-circuiter sans toucher au storage.
    expect(await controller.shouldShow(), isFalse);
  });

  test('controller.markConfirmed → shouldShow reste false', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = NudgeService(storage: NudgeStorage(prefs: prefs));
    final controller = IosAddToHomeController(nudgeService: service);

    await controller.markConfirmed();
    expect(await service.isSeen(NudgeIds.iosAddToHome), isTrue);
    expect(await controller.shouldShow(), isFalse);
  });

  test('controller.markDismissed → lastShown enregistré', () async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final service = NudgeService(storage: NudgeStorage(prefs: prefs));
    final controller = IosAddToHomeController(nudgeService: service);

    await controller.markDismissed();
    expect(await service.lastShown(NudgeIds.iosAddToHome), isNotNull);
    expect(await service.isSeen(NudgeIds.iosAddToHome), isFalse);
  });
}
