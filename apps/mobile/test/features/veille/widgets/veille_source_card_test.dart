import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config.dart';
import 'package:facteur/features/veille/models/veille_delivery.dart';
import 'package:facteur/features/veille/providers/veille_repository_provider.dart';
import 'package:facteur/features/veille/repositories/veille_repository.dart';
import 'package:facteur/features/veille/widgets/veille_source_card.dart';

/// Repo factice : seuls `getSourceExamples` est utilisé par les tests.
/// Le reste throw — si un test du widget appelle ces méthodes, c'est un bug
/// d'instrumentation à corriger plutôt que d'accepter silencieusement.
class _FakeRepo implements VeilleRepository {
  final List<VeilleSourceExample> examples;
  final Object? throwOnFetch;

  _FakeRepo({this.examples = const [], this.throwOnFetch});

  @override
  Future<List<VeilleSourceExample>> getSourceExamples(String sourceId) async {
    if (throwOnFetch != null) {
      throw throwOnFetch is Exception
          ? throwOnFetch as Exception
          : Exception(throwOnFetch.toString());
    }
    return examples;
  }

  @override
  noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} non mocké');
}

const _source = VeilleSource(
  id: 'src-1',
  letter: 'L',
  name: 'Le Monde',
);

Widget _wrap(ProviderContainer container) {
  return UncontrolledProviderScope(
    container: container,
    child: MaterialApp(
      home: Scaffold(
        body: VeilleSourceCard(
          source: _source,
          inVeille: true,
          isAlreadyFollowed: false,
          onToggle: () {},
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('toggle "Voir 2 exemples récents" → expand affiche les items',
      (tester) async {
    final repo = _FakeRepo(
      examples: const [
        VeilleSourceExample(
          title: 'Article récent 1',
          url: 'https://lemonde.fr/a1',
          publishedAt: null,
          excerpt: 'Excerpt 1',
        ),
        VeilleSourceExample(
          title: 'Article récent 2',
          url: 'https://lemonde.fr/a2',
          publishedAt: null,
          excerpt: 'Excerpt 2',
        ),
      ],
    );
    final container = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    // Avant tap : pas d'items visibles.
    expect(find.text('Article récent 1'), findsNothing);

    await tester.tap(find.text('Voir 2 exemples récents'));
    await tester.pump(); // start expand
    await tester.pump(const Duration(milliseconds: 250)); // settle AnimatedSize
    await tester.pump(); // future resolves

    expect(find.text('Article récent 1'), findsOneWidget);
    expect(find.text('Article récent 2'), findsOneWidget);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('liste vide → fallback "Pas d\'exemples récents"',
      (tester) async {
    final repo = _FakeRepo(examples: const []);
    final container = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Voir 2 exemples récents'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text("Pas d'exemples récents disponibles."), findsOneWidget);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });

  testWidgets('erreur réseau → fallback affiché (pas de crash)',
      (tester) async {
    final repo = _FakeRepo(throwOnFetch: 'boom');
    final container = ProviderContainer(
      overrides: [veilleRepositoryProvider.overrideWithValue(repo)],
    );

    await tester.pumpWidget(_wrap(container));
    await tester.pump();

    await tester.tap(find.text('Voir 2 exemples récents'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump();

    expect(find.text("Pas d'exemples récents disponibles."), findsOneWidget);

    container.dispose();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
  });
}
