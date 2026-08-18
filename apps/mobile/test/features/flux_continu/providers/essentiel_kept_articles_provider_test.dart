import 'dart:convert';

import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/essentiel_kept_articles_provider.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Archive du jour des articles gardés (bug-essentiel-gardes-disparaissent).
///
/// L'invariant produit verrouillé ici : **un gardé est gardé pour toute la
/// journée** — le payload survit au kill de l'app même quand le backend cesse
/// de servir l'article (éviction « Essentiel vivant » après lecture).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  String todayKey() => TourneeProgressService.dayKey(DateTime.now());

  EssentielArticle article(
    String id, {
    bool isRead = false,
    String title = 'Titre',
  }) =>
      EssentielArticle(
        contentId: id,
        title: '$title $id',
        url: 'https://example.com/$id',
        publishedAt: DateTime.utc(2026, 8, 13),
        sourceName: 'Source $id',
        sourceLetter: 'S',
        sectionLabel: '',
        rank: 1,
        isRead: isRead,
      );

  setUp(() => SharedPreferences.setMockInitialValues({}));

  ProviderContainer makeContainer() {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    return container;
  }

  Future<EssentielKeptArticlesNotifier> hydrated(
    ProviderContainer container,
  ) async {
    final notifier = container.read(essentielKeptArticlesProvider.notifier);
    while (!container.read(essentielKeptArticlesProvider).hydrated) {
      await Future<void>.delayed(Duration.zero);
    }
    return notifier;
  }

  test('archive les gardés résolus et les expose par id', () async {
    final container = makeContainer();
    final notifier = await hydrated(container);

    notifier.sync(
      resolved: [article('c-1'), article('c-2')],
      keptIds: {'c-1', 'c-2'},
    );

    expect(
      container.read(essentielKeptArticlesProvider).byId.keys,
      containsAll(<String>['c-1', 'c-2']),
    );
  });

  test('n\'archive que ce qui est réellement gardé', () async {
    final container = makeContainer();
    final notifier = await hydrated(container);

    // `resolved` porte un article que le tri a rejeté : il ne doit pas entrer.
    notifier.sync(
      resolved: [article('c-1'), article('c-2')],
      keptIds: {'c-1'},
    );

    expect(container.read(essentielKeptArticlesProvider).byId.keys, ['c-1']);
  });

  test('un gardé évincé du pool survit au redémarrage', () async {
    final first = makeContainer();
    final notifier = await hydrated(first);
    notifier.sync(
      resolved: [article('c-1', isRead: true), article('c-2')],
      keptIds: {'c-1', 'c-2'},
    );
    // L'écriture SharedPreferences est asynchrone (fire-and-forget).
    await Future<void>.delayed(Duration.zero);

    // Cold-boot : le backend n'a **plus** `c-1` (lu ⇒ évincé par le blend
    // live), donc rien à re-résoudre. C'est exactement le cas du bug.
    final second = makeContainer();
    await hydrated(second);

    final archived = second.read(essentielKeptArticlesProvider).byId;
    expect(archived.keys, containsAll(<String>['c-1', 'c-2']));
    expect(archived['c-1']!.isRead, isTrue);
    expect(archived['c-1']!.title, 'Titre c-1');
  });

  test('rafraîchit le payload quand le pool sert une version plus fraîche',
      () async {
    final container = makeContainer();
    final notifier = await hydrated(container);

    notifier.sync(resolved: [article('c-1')], keptIds: {'c-1'});
    expect(
      container.read(essentielKeptArticlesProvider).byId['c-1']!.isRead,
      isFalse,
    );

    notifier.sync(resolved: [article('c-1', isRead: true)], keptIds: {'c-1'});
    expect(
      container.read(essentielKeptArticlesProvider).byId['c-1']!.isRead,
      isTrue,
    );
  });

  test('un sync sans changement ne réémet pas l\'état', () async {
    final container = makeContainer();
    final notifier = await hydrated(container);

    notifier.sync(resolved: [article('c-1')], keptIds: {'c-1'});
    final before = container.read(essentielKeptArticlesProvider);

    // Nouvelle instance, mêmes champs : la carte réalloue ses articles à chaque
    // réponse réseau, l'archive ne doit pas réécrire pour autant.
    notifier.sync(resolved: [article('c-1')], keptIds: {'c-1'});

    expect(
      identical(container.read(essentielKeptArticlesProvider), before),
      isTrue,
    );
  });

  test('« Refaire ? » vide l\'archive avec les décisions', () async {
    final container = makeContainer();
    final notifier = await hydrated(container);

    notifier.sync(
      resolved: [article('c-1'), article('c-2')],
      keptIds: {'c-1', 'c-2'},
    );
    // `restart()` remet les décisions à zéro ⇒ plus aucun gardé.
    notifier.sync(resolved: const [], keptIds: const {});

    expect(container.read(essentielKeptArticlesProvider).byId, isEmpty);
  });

  test('n\'élague rien avant d\'avoir été hydratée', () async {
    final container = makeContainer();
    // Pas de `hydrated()` : on tape sur le notifier pendant sa relecture.
    final notifier = container.read(essentielKeptArticlesProvider.notifier);
    expect(container.read(essentielKeptArticlesProvider).hydrated, isFalse);

    // Un build avec un tri pas encore résolu ne doit pas effacer l'archive en
    // cours de relecture — il ne fait qu'ajouter.
    notifier.sync(resolved: [article('c-9')], keptIds: {'c-9'});
    expect(container.read(essentielKeptArticlesProvider).byId.keys, ['c-9']);

    await hydrated(container);
    expect(container.read(essentielKeptArticlesProvider).byId.keys, ['c-9']);
  });

  test('l\'archive relue ne perd pas ce qui a été gardé pendant la relecture',
      () async {
    SharedPreferences.setMockInitialValues({
      essentielKeptPrefsKey(todayKey()): jsonEncode([article('c-1').toJson()]),
    });

    final container = makeContainer();
    final notifier = container.read(essentielKeptArticlesProvider.notifier);
    notifier.sync(resolved: [article('c-2')], keptIds: {'c-1', 'c-2'});
    await hydrated(container);

    expect(
      container.read(essentielKeptArticlesProvider).byId.keys,
      containsAll(<String>['c-1', 'c-2']),
    );
  });

  test('purge les archives des jours précédents', () async {
    SharedPreferences.setMockInitialValues({
      '${kEssentielKeptPrefsKeyPrefix}2020-01-01':
          jsonEncode([article('vieux').toJson()]),
    });

    final container = makeContainer();
    await hydrated(container);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getKeys(), isNot(contains('${kEssentielKeptPrefsKeyPrefix}2020-01-01')));
    expect(container.read(essentielKeptArticlesProvider).byId, isEmpty);
  });
}
