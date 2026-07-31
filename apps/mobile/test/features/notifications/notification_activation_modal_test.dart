import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/features/notifications/widgets/notification_activation_modal.dart';

class _NoopAnalytics implements AnalyticsService {
  @override
  noSuchMethod(Invocation invocation) async {}
}

Widget _wrapModal(ActivationTrigger trigger) {
  return ProviderScope(
    overrides: [
      analyticsServiceProvider.overrideWithValue(_NoopAnalytics()),
    ],
    child: MaterialApp(
      home: Scaffold(
        body: NotificationActivationModal(trigger: trigger),
      ),
    ),
  );
}

void main() {
  late Directory tempDir;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('hive_modal_test_');
    Hive.init(tempDir.path);
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  testWidgets(
    'trigger=veille → titre + CTA dédiés, pas de section "Bonnes nouvelles"',
    (tester) async {
      await tester.pumpWidget(_wrapModal(ActivationTrigger.veille));
      await tester.pump();

      expect(
        find.text('Te prévenir quand ta veille est prête ?'),
        findsOneWidget,
      );
      expect(find.text("M'en informer"), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
      expect(find.text('À quel moment ?'), findsNothing);
      expect(find.text('🌱 Bonnes nouvelles du jour'), findsNothing);
    },
  );

  testWidgets(
    'trigger=onboarding → titre digest + CTA "Activer ton Facteur"',
    (tester) async {
      await tester.pumpWidget(_wrapModal(ActivationTrigger.onboarding));
      await tester.pump();

      expect(find.text("Mieux s'informer, à son rythme"), findsOneWidget);
      expect(find.text('Activer ton Facteur'), findsOneWidget);
      // Le digest est le seul trigger à proposer l'horaire et le canal
      // Bonnes nouvelles.
      expect(find.text('À quel moment ?'), findsOneWidget);
      expect(find.text('🌱 Bonnes nouvelles du jour'), findsOneWidget);
    },
  );

  testWidgets(
    'trigger=alert → copy cloche, ni horaire ni "Bonnes nouvelles"',
    (tester) async {
      await tester.pumpWidget(_wrapModal(ActivationTrigger.alert));
      await tester.pump();

      expect(
        find.text('Te prévenir quand cette source publie ?'),
        findsOneWidget,
      );
      expect(find.text('Activer la cloche'), findsOneWidget);
      expect(find.text('Plus tard'), findsOneWidget);
      expect(find.text('À quel moment ?'), findsNothing);
      expect(find.text('🌱 Bonnes nouvelles du jour'), findsNothing);
    },
  );
}
