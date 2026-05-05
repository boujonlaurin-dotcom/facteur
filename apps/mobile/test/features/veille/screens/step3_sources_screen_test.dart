// Test : Step 3 sources — bouton « Réessayer » présent sur erreur API.
//
// Régression bug `bug-veille-suggestions-sources-pending-rollback` :
// le bouton retry avait été retiré dans PR2 #562 (refonte UI sources rankées),
// laissant l'user bloqué sur le mock fallback sans CTA pour relancer la
// génération.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_suggestion.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';
import 'package:facteur/features/veille/screens/steps/step3_sources_screen.dart';

class _FakeRepo implements VeilleRepository {
  int suggestSourcesCallCount = 0;

  @override
  Future<VeilleSourceSuggestionsResponse> suggestSources({
    required String themeId,
    List<String> topicLabels = const [],
    List<String> excludeSourceIds = const [],
    String? purpose,
    String? purposeOther,
    String? editorialBrief,
  }) async {
    suggestSourcesCallCount += 1;
    throw const VeilleApiException('boom', statusCode: 503);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

ProviderContainer _container(_FakeRepo repo) {
  final container = ProviderContainer(
    overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
  );
  // Pré-configure un thème + un topic pour que params != null et que
  // le bouton "Réessayer" soit câblé.
  final notifier = container.read(veilleConfigProvider.notifier);
  notifier.selectTheme('tech');
  notifier.toggleTopic('ia');
  return container;
}

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: Step3SourcesScreen(onClose: () {}),
      ),
    ),
  );
}

void main() {
  testWidgets(
    'erreur API → fallback affiche bouton Réessayer cliquable',
    (tester) async {
      final repo = _FakeRepo();
      final container = _container(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      // Attente : 1er fetch déclenché par le constructeur du notifier.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.suggestSourcesCallCount, 1);
      expect(find.text('Suggestions indisponibles, conserve ta sélection.'),
          findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Le tap déclenche un nouveau fetch — preuve que le câblage
      // refreshKeepingChecked passe bien.
      expect(repo.suggestSourcesCallCount, 2);
    },
  );
}
