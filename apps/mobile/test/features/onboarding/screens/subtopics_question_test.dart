import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/providers/custom_topics_provider.dart';
import 'package:facteur/features/onboarding/providers/onboarding_provider.dart';
import 'package:facteur/features/onboarding/screens/questions/subtopics_question.dart';

/// Fake notifier renvoyant une liste figée de sujets « saved », sans réseau.
class _FakeCustomTopicsNotifier extends CustomTopicsNotifier {
  _FakeCustomTopicsNotifier(this._topics);
  final List<UserTopicProfile> _topics;

  @override
  Future<List<UserTopicProfile>> build() async => _topics;
}

void main() {
  setUpAll(() {
    Hive.init(Directory.systemTemp.createTempSync('onb_subtopics_test').path);
  });

  ProviderContainer makeContainer(List<UserTopicProfile> saved) {
    final container = ProviderContainer(
      overrides: [
        customTopicsProvider.overrideWith(
          () => _FakeCustomTopicsNotifier(saved),
        ),
        // Pas d'entités backend → carte simple.
        popularEntitiesProvider.overrideWith((ref, theme) async => const []),
        analyticsServiceProvider.overrideWithValue(AnalyticsService.disabled()),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  Widget buildTestWidget(ProviderContainer container) {
    return UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: const Scaffold(body: SubtopicsQuestion()),
      ),
    );
  }

  testWidgets(
      'les chips custom « saved » sont dérivés du provider, filtrés par thème',
      (tester) async {
    final container = makeContainer(const [
      UserTopicProfile(id: 'k1', name: 'Kylian Mbappé', slugParent: 'tech'),
      // Sujet d'un thème NON sélectionné : ne doit apparaître sur aucune carte.
      UserTopicProfile(id: 'o1', name: 'Autre', slugParent: 'sport'),
    ]);
    container.read(onboardingProvider.notifier).bypassOnboarding();

    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    expect(find.text('Kylian Mbappé'), findsOneWidget);
    expect(find.text('Autre'), findsNothing);
  });

  testWidgets('le CTA d\'ajout ouvre la fenêtre de désambiguïsation',
      (tester) async {
    final container = makeContainer(const []);
    container.read(onboardingProvider.notifier).bypassOnboarding();

    await tester.pumpWidget(buildTestWidget(container));
    await tester.pumpAndSettle();

    // Le champ inline a disparu ; on ouvre EntityAddSheet à la place.
    expect(find.text('Ajouter un sujet personnalisé'), findsNothing);

    await tester.tap(find.text('Ajouter un sujet').first);
    await tester.pumpAndSettle();

    // La bottom sheet (EntityAddSheet) est montée : titre + champ de saisie.
    expect(find.text('Ajouter un sujet personnalisé'), findsOneWidget);
  });
}
