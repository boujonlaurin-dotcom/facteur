import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/onboarding/services/onboarding_push_priming.dart';
import 'package:facteur/features/onboarding/widgets/onboarding_notif_priming.dart';

class _RecordingAnalytics implements AnalyticsService {
  final List<String> calls = [];

  @override
  dynamic noSuchMethod(Invocation invocation) async {
    calls.add(invocation.memberName.toString());
  }
}

/// Fake du seam d'amorce : enregistre les appels sans toucher Firebase/Hive.
class _FakePriming implements OnboardingPushPriming {
  bool acceptCalled = false;
  bool refuseCalled = false;

  @override
  Future<bool> hasSeenPriming() async => false;

  @override
  Future<bool> acceptAndRegister() async {
    acceptCalled = true;
    return true;
  }

  @override
  Future<void> refuse() async {
    refuseCalled = true;
  }
}

Widget _host({
  required OnboardingPushPriming priming,
  required AnalyticsService analytics,
}) {
  return ProviderScope(
    overrides: [
      onboardingPushPrimingProvider.overrideWithValue(priming),
      analyticsServiceProvider.overrideWithValue(analytics),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: Consumer(
          builder: (context, ref, _) => Center(
            child: ElevatedButton(
              onPressed: () =>
                  showOnboardingNotifPriming(context, ref, step: 3),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_priming_test_');
    Hive.init(tempDir.path);
  });

  tearDown(() async {
    if (Hive.isBoxOpen('settings')) {
      await Hive.box<dynamic>('settings').clear();
    }
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets('affiche le titre + les deux CTA', (tester) async {
    await tester.pumpWidget(
      _host(priming: _FakePriming(), analytics: _RecordingAnalytics()),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Activer les rappels ?'), findsOneWidget);
    expect(find.text('Activer les rappels'), findsOneWidget);
    expect(find.text('Plus tard'), findsOneWidget);
  });

  testWidgets('accept → acceptAndRegister appelé + event accepted + fermeture',
      (tester) async {
    final priming = _FakePriming();
    final analytics = _RecordingAnalytics();
    await tester.pumpWidget(_host(priming: priming, analytics: analytics));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Activer les rappels'));
    await tester.pumpAndSettle();

    expect(priming.acceptCalled, isTrue);
    expect(
      analytics.calls.any((c) => c.contains('PrimingAccepted')),
      isTrue,
    );
    // Dialog fermé.
    expect(find.text('Activer les rappels ?'), findsNothing);
  });

  testWidgets(
    'refus (« Plus tard ») appelle refuse() + event refused, sans accept',
    (tester) async {
      final priming = _FakePriming();
      final analytics = _RecordingAnalytics();
      await tester.pumpWidget(_host(priming: priming, analytics: analytics));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();

      expect(priming.refuseCalled, isTrue);
      expect(priming.acceptCalled, isFalse);
      expect(
        analytics.calls.any((c) => c.contains('PrimingRefused')),
        isTrue,
      );
      // Dialog fermé.
      expect(find.text('Activer les rappels ?'), findsNothing);
    },
  );

  // Le contrat Hive du seam se teste hors widget : `refuse()` fait de l'I/O
  // fichier réelle, or la lancer dans un callback pompé sous fake-async
  // (`pumpAndSettle`) provoque un deadlock d'`openBox` concurrent. Ici, en
  // async réel, l'I/O aboutit normalement.
  test('refuse() pose notif_early_priming_seen SANS notif_modal_seen', () async {
    await const OnboardingPushPriming().refuse();

    final box = await Hive.openBox<dynamic>('settings');
    expect(box.get('notif_early_priming_seen'), isTrue);
    // Le gate de la modale d'activation quotidienne NE doit PAS être posé.
    expect(box.get('notif_modal_seen'), isNull);
  });
}
