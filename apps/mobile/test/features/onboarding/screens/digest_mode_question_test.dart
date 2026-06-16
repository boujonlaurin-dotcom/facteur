import 'dart:io';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/onboarding/onboarding_strings.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:facteur/features/onboarding/screens/questions/digest_mode_question.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('digest_mode_test').path);
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  Widget buildTestWidget(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(body: DigestModeQuestion()),
      ),
    );
  }

  testWidgets(
    'mode serein : plus de CTA personnalisation, note paramètres visible',
    (tester) async {
      final container = makeContainer();
      await tester.pumpWidget(buildTestWidget(container));
      await tester.pumpAndSettle();

      expect(find.text(OnboardingStrings.personalizeSereinCta), findsNothing);
      expect(
          find.text(OnboardingStrings.digestModeAnytimeNote), findsOneWidget);

      await tester.tap(find.text('Oui, rester serein'));
      await tester.pump();
      expect(
        container.read(onboardingProvider).answers.digestMode,
        'serein',
      );

      await tester.tap(find.text('Non, tout voir'));
      await tester.pump();
      expect(
        container.read(onboardingProvider).answers.digestMode,
        'pour_vous',
      );

      await tester.pump(const Duration(seconds: 2));
    },
  );
}
