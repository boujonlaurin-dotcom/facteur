// Couvre la régression PR #563 : la subscription helper du notifier
// `veilleConfigProvider` doit garder vivant le provider `family.autoDispose`
// de suggestions jusqu'à ce que l'écran cible (Step2/Step3) ait monté son
// `ref.watch`. Sinon le provider est disposé entre les deux et l'écran
// affiche un skeleton de loading au lieu des données pré-fetchées.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/api/providers.dart';
import 'package:facteur/features/veille/models/veille_suggestion.dart';
import 'package:facteur/features/veille/providers/veille_config_provider.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/providers/veille_suggestions_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';

class _MockApiClient extends Mock implements ApiClient {}

class _FakeRepo extends VeilleRepository {
  _FakeRepo(super.apiClient);

  int sourcesFetchCount = 0;
  int topicsFetchCount = 0;

  @override
  Future<List<VeilleTopicSuggestion>> suggestTopics({
    required String themeId,
    required String themeLabel,
    List<String> selectedTopicIds = const [],
    List<String> excludeTopicIds = const [],
    String? purpose,
    String? purposeOther,
    String? editorialBrief,
  }) async {
    topicsFetchCount++;
    return const [
      VeilleTopicSuggestion(
        topicId: 'sugg-1',
        label: 'Suggestion 1',
        reason: null,
      ),
    ];
  }

  @override
  Future<VeilleSourceSuggestionsResponse> suggestSources({
    required String themeId,
    List<String> topicLabels = const [],
    List<String> excludeSourceIds = const [],
    String? purpose,
    String? purposeOther,
    String? editorialBrief,
  }) async {
    sourcesFetchCount++;
    return const VeilleSourceSuggestionsResponse(
      sources: [
        VeilleSourceSuggestion(
          sourceId: 'src-1',
          name: 'Source 1',
          url: 'https://example.com',
          feedUrl: 'https://example.com/feed',
          theme: 'tech',
        ),
      ],
    );
  }
}

/// Widget harness qui mime la logique de bascule de `VeilleConfigScreen` :
/// pendant `state.isLoading`, on rend un placeholder (équivalent
/// `FlowLoadingScreen`) ; sinon, on rend un Consumer qui fait un
/// `ref.watch` sur `veilleSourceSuggestionsProvider(params)` (équivalent
/// `Step3SourcesScreen`). Le test vérifie qu'à l'arrivée sur Step3, le
/// provider est `data` (pas `loading`) — donc pas de fetch additionnel.
class _Harness extends ConsumerWidget {
  const _Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    if (state.isLoading) {
      return const Center(
        key: ValueKey('halo'),
        child: Text('halo'),
      );
    }

    if (state.step != 3) {
      return const SizedBox.shrink(key: ValueKey('not-step3'));
    }

    final params = notifier.sourcesParamsFromState();
    if (params == null) {
      return const SizedBox.shrink(key: ValueKey('no-params'));
    }
    final async = ref.watch(veilleSourceSuggestionsProvider(params));
    return async.when(
      loading: () => const Center(
        key: ValueKey('step3-loading'),
        child: CircularProgressIndicator(),
      ),
      error: (_, __) => const SizedBox.shrink(key: ValueKey('step3-error')),
      data: (resp) => Center(
        key: const ValueKey('step3-data'),
        child: Text('count=${resp.sources.length}'),
      ),
    );
  }
}

void main() {
  late _MockApiClient apiClient;
  late _FakeRepo repo;

  setUp(() {
    apiClient = _MockApiClient();
    repo = _FakeRepo(apiClient);
  });

  ProviderContainer makeContainer() => ProviderContainer(
        overrides: [
          apiClientProvider.overrideWithValue(apiClient),
          veilleRepositoryProvider.overrideWithValue(repo),
        ],
      );

  testWidgets(
    'Step2→Step3 : Step3 affiche les sources sans skeleton (pas de race autoDispose)',
    (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.selectTheme('tech');
      notifier.toggleTopic('topic-a');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(home: Scaffold(body: _Harness())),
        ),
      );

      // Step1→2 : kicker la transition, pump au-delà de minDelay (1.5 s).
      notifier.goNext();
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump();
      expect(container.read(veilleConfigProvider).step, 2);

      // Sélectionne une suggestion et trigger Step2→3.
      notifier.toggleSuggestion('sugg-1');
      notifier.goNext();
      await tester.pump(const Duration(milliseconds: 1700));
      // Frame supplémentaire pour laisser passer le post-frame _disposePending
      // ET le rebuild qui mount le "Step3" dans le harness.
      await tester.pump();

      expect(container.read(veilleConfigProvider).step, 3);

      // Assertion principale : pas de skeleton sur Step3 — les sources sont
      // déjà là grâce au pré-fetch (le provider n'a pas été disposé/recréé
      // entre l'animation halo et le mount de Step3).
      expect(find.byKey(const ValueKey('step3-loading')), findsNothing);
      expect(find.byKey(const ValueKey('step3-data')), findsOneWidget);
      expect(find.text('count=1'), findsOneWidget);

      // Le provider a été fetché exactement une fois pour les sources.
      // Sans le fix : 2 fetches (un pour le pré-fetch, un pour la recréation
      // après autoDispose au mount de Step3).
      expect(repo.sourcesFetchCount, 1);
    },
  );

  testWidgets(
    'Step1→Step2 : le pré-fetch topics survit aussi à la transition',
    (tester) async {
      final container = makeContainer();
      addTearDown(container.dispose);

      final notifier = container.read(veilleConfigProvider.notifier);
      notifier.selectTheme('tech');

      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: const MaterialApp(
            home: Scaffold(body: _Step2Harness()),
          ),
        ),
      );

      notifier.goNext();
      await tester.pump(const Duration(milliseconds: 1700));
      await tester.pump();

      expect(container.read(veilleConfigProvider).step, 2);
      expect(find.byKey(const ValueKey('step2-loading')), findsNothing);
      expect(find.byKey(const ValueKey('step2-data')), findsOneWidget);
      expect(repo.topicsFetchCount, 1);
    },
  );
}

class _Step2Harness extends ConsumerWidget {
  const _Step2Harness();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(veilleConfigProvider);
    final notifier = ref.read(veilleConfigProvider.notifier);

    if (state.isLoading) {
      return const Center(key: ValueKey('halo'), child: Text('halo'));
    }
    if (state.step != 2) {
      return const SizedBox.shrink(key: ValueKey('not-step2'));
    }
    final params = notifier.topicsParamsFromState();
    if (params == null) {
      return const SizedBox.shrink(key: ValueKey('no-params'));
    }
    final async = ref.watch(veilleTopicSuggestionsProvider(params));
    return async.when(
      loading: () => const Center(
        key: ValueKey('step2-loading'),
        child: CircularProgressIndicator(),
      ),
      error: (_, __) => const SizedBox.shrink(key: ValueKey('step2-error')),
      data: (items) => Center(
        key: const ValueKey('step2-data'),
        child: Text('topics=${items.length}'),
      ),
    );
  }
}
