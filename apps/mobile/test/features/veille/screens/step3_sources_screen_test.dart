// Test : Step 3 sources — fallback erreur API + CTA disabled tant qu'aucune
// source réelle n'est sélectionnée.
//
// - Régression `bug-veille-suggestions-sources-pending-rollback` : un bouton
//   « Réessayer » doit rester accessible quand `/suggestions/sources` échoue.
// - A2/A3 (`bug-veille-config-without-sources`) : la liste mock cliquable a
//   été retirée du fallback, le CTA « Continuer » est désactivé tant qu'aucune
//   source avec `apiSourceId` n'est sélectionnée.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_suggestion.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';
import 'package:facteur/features/veille/screens/steps/step3_sources_screen.dart';

class _FakeRepoError implements VeilleRepository {
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

class _FakeRepoOk implements VeilleRepository {
  final VeilleSourceSuggestionsResponse response;
  _FakeRepoOk(this.response);

  @override
  Future<VeilleSourceSuggestionsResponse> suggestSources({
    required String themeId,
    List<String> topicLabels = const [],
    List<String> excludeSourceIds = const [],
    String? purpose,
    String? purposeOther,
    String? editorialBrief,
  }) async =>
      response;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

ProviderContainer _container(VeilleRepository repo) {
  final container = ProviderContainer(
    overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
  );
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
      final repo = _FakeRepoError();
      final container = _container(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.suggestSourcesCallCount, 1);
      expect(find.text('On n\'a pas pu charger les suggestions.'),
          findsOneWidget);
      expect(find.text('Réessayer'), findsOneWidget);

      await tester.tap(find.text('Réessayer'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(repo.suggestSourcesCallCount, 2);
    },
  );

  testWidgets(
    'CTA Continuer désactivé tant qu\'aucune source réelle sélectionnée',
    (tester) async {
      // Repo en erreur → fallback sans liste mock cliquable, donc 0 source
      // réelle possible jusqu'à ce que l'user passe par « + Ajouter une source ».
      final repo = _FakeRepoError();
      final container = _container(repo);
      addTearDown(container.dispose);

      await tester.pumpWidget(_wrap(container));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      // Hint visible au-dessus du CTA.
      expect(
        find.text('Sélectionne au moins une source pour continuer.'),
        findsOneWidget,
      );

      // realSelectedSourceCount == 0 → CTA désactivé.
      final state = container.read(veilleConfigProvider);
      expect(state.realSelectedSourceCount, 0);
    },
  );
}
