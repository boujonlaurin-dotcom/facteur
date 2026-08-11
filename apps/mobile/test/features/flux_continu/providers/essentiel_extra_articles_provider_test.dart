import 'dart:convert';

import 'package:facteur/features/flux_continu/providers/essentiel_extra_articles_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockEssentielRepository extends Mock implements EssentielRepository {}

/// Articles rapatriés par « Plus d'articles ? » quand la réserve locale est
/// épuisée (Story 33.3). Ce que ces tests verrouillent, c'est l'invariant
/// produit : **jamais un doublon, jamais une décision perdue au redémarrage**.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockEssentielRepository repo;

  String todayKey() => TourneeProgressService.dayKey(DateTime.now());

  Map<String, dynamic> payload(String id) => {
        'content_id': id,
        'title': 'Réseau $id',
        'url': 'https://example.com/$id',
        'published_at': DateTime(2026, 5, 23).toIso8601String(),
        'source': {'id': 's-$id', 'name': 'Source $id'},
        'source_letter': 'S',
        'section_label': '',
        'rank': 1,
      };

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _MockEssentielRepository();
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      essentielRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  Future<EssentielExtraArticlesNotifier> hydrated(
    ProviderContainer container,
  ) async {
    final notifier = container.read(essentielExtraArticlesProvider.notifier);
    // L'hydratation SharedPreferences est asynchrone.
    while (!container.read(essentielExtraArticlesProvider).hydrated) {
      await Future<void>.delayed(Duration.zero);
    }
    return notifier;
  }

  test('rapatrie deux articles et les expose dans l\'ordre servi', () async {
    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [payload('n-1'), payload('n-2')]);

    final container = makeContainer();
    final notifier = await hydrated(container);

    final fresh = await notifier.fetchMore(excludeIds: const ['c-1']);

    expect(fresh.map((a) => a.contentId), ['n-1', 'n-2']);
    expect(
      container.read(essentielExtraArticlesProvider).articles.length,
      2,
    );
  });

  test('l\'exclusion envoyée porte aussi ce qui a déjà été rapatrié', () async {
    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [payload('n-1')]);

    final container = makeContainer();
    final notifier = await hydrated(container);
    await notifier.fetchMore(excludeIds: const ['c-1']);

    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [payload('n-2')]);
    await notifier.fetchMore(excludeIds: const ['c-1']);

    final calls = verify(() => repo.fetchMore(
          excludeIds: captureAny(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).captured.cast<List<String>>();
    expect(calls.first, ['c-1']);
    expect(calls.last, containsAll(<String>['c-1', 'n-1']),
        reason: 'le 2e appel exclut le 1er rapatriement');
  });

  test('un article déjà porté par le client est écarté, même servi', () async {
    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [payload('c-1'), payload('n-1')]);

    final container = makeContainer();
    final notifier = await hydrated(container);
    final fresh = await notifier.fetchMore(excludeIds: const ['c-1']);

    expect(fresh.map((a) => a.contentId), ['n-1'],
        reason: 'le doublon servi par le backend ne doit jamais entrer');
  });

  test('rien d\'inédit ⇒ liste vide, et rien n\'est persisté', () async {
    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => const []);

    final container = makeContainer();
    final notifier = await hydrated(container);

    expect(await notifier.fetchMore(excludeIds: const []), isEmpty);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(essentielExtraPrefsKey(todayKey())), isNull);
  });

  test('échec réseau ⇒ liste vide, jamais d\'exception remontée', () async {
    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => null);

    final container = makeContainer();
    final notifier = await hydrated(container);

    expect(await notifier.fetchMore(excludeIds: const []), isEmpty);
  });

  test('un appel en vol absorbe les suivants (garde anti double-tap)',
      () async {
    var calls = 0;
    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async {
      calls++;
      await Future<void>.delayed(const Duration(milliseconds: 10));
      return [payload('n-1')];
    });

    final container = makeContainer();
    final notifier = await hydrated(container);

    final results = await Future.wait([
      notifier.fetchMore(excludeIds: const []),
      notifier.fetchMore(excludeIds: const []),
      notifier.fetchMore(excludeIds: const []),
    ]);

    expect(calls, 1);
    expect(results.expand((r) => r).length, 1,
        reason: 'un seul rapatriement, pas trois fois le même article');
  });

  test('cold boot : les articles rapatriés sont relus, dans le même ordre',
      () async {
    when(() => repo.fetchMore(
          excludeIds: any(named: 'excludeIds'),
          limit: any(named: 'limit'),
        )).thenAnswer((_) async => [payload('n-1'), payload('n-2')]);

    final first = makeContainer();
    await (await hydrated(first)).fetchMore(excludeIds: const []);
    // Laisse le `_persist()` en fire-and-forget aboutir.
    await Future<void>.delayed(Duration.zero);

    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(essentielExtraPrefsKey(todayKey()));
    expect(raw, isNotNull);
    expect((jsonDecode(raw!) as List).length, 2);

    // Nouveau process : aucune requête réseau, l'état revient du disque.
    final second = makeContainer();
    await hydrated(second);
    expect(
      second
          .read(essentielExtraArticlesProvider)
          .articles
          .map((a) => a.contentId),
      ['n-1', 'n-2'],
      reason: 'l\'ordre des articles déjà affichés ne doit pas être rebattu',
    );
  });

  test('la clé d\'un jour révolu est purgée à l\'hydratation', () async {
    SharedPreferences.setMockInitialValues({
      essentielExtraPrefsKey('2020-01-01'): jsonEncode([payload('vieux')]),
    });

    final container = makeContainer();
    await hydrated(container);

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(essentielExtraPrefsKey('2020-01-01')), isNull);
    expect(container.read(essentielExtraArticlesProvider).articles, isEmpty);
  });

  // ── Gardes du prefetch automatique (Story 33.4) ──────────────────────────
  //
  // Sans elles, une pile dont le pool est sec redemanderait la suite à chaque
  // frame : c'est le seul chemin de la story qui puisse produire une boucle
  // réseau, et il part tout seul (aucun geste utilisateur).

  group('prefetch automatique', () {
    test('un retour vide pose un cooldown : pas de second appel réseau',
        () async {
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const []);

      final container = makeContainer();
      final notifier = await hydrated(container);

      await notifier.fetchMore(excludeIds: const []);
      await notifier.fetchMore(excludeIds: const []);

      verify(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).called(1);
      expect(notifier.canAutoFetch(), isFalse);
    });

    test('le cooldown expire au bout de ${kTriageExhaustedCooldown.inMinutes} '
        'minutes', () async {
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const []);

      final container = makeContainer();
      final notifier = await hydrated(container);
      final t0 = DateTime(2026, 8, 11, 9);
      await notifier.fetchMore(excludeIds: const [], now: t0);

      expect(
        notifier.canAutoFetch(now: t0.add(const Duration(minutes: 9))),
        isFalse,
      );
      expect(
        notifier.canAutoFetch(now: t0.add(kTriageExhaustedCooldown)),
        isTrue,
      );
    });

    test('un geste utilisateur (force) ignore le cooldown', () async {
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const []);

      final container = makeContainer();
      final notifier = await hydrated(container);
      await notifier.fetchMore(excludeIds: const []);

      await notifier.fetchMore(excludeIds: const [], force: true);

      verify(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).called(2);
    });

    test('un échec réseau n\'est PAS un épuisement', () async {
      // Une coupure de trois secondes ne doit pas figer la pile dix minutes :
      // le prochain swipe doit pouvoir retenter.
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => null);

      final container = makeContainer();
      final notifier = await hydrated(container);

      await notifier.fetchMore(excludeIds: const []);

      expect(notifier.canAutoFetch(), isTrue);
    });

    test('$kTriageMaxAutoFetches prefetchs au maximum', () async {
      var served = 0;
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [payload('n-${served++}')]);

      final container = makeContainer();
      final notifier = await hydrated(container);

      for (var i = 0; i < kTriageMaxAutoFetches + 3; i++) {
        await notifier.fetchMore(excludeIds: const []);
      }

      expect(notifier.autoFetchCount, kTriageMaxAutoFetches);
      verify(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).called(kTriageMaxAutoFetches);
      // Le plafond est celui du **prefetch** : le CTA reste actionnable.
      expect(await notifier.fetchMore(excludeIds: const [], force: true),
          isNotEmpty);
    });

    test('le lot non vide rouvre la vanne après un épuisement', () async {
      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => const []);

      final container = makeContainer();
      final notifier = await hydrated(container);
      await notifier.fetchMore(excludeIds: const []);
      expect(notifier.canAutoFetch(), isFalse);

      when(() => repo.fetchMore(
            excludeIds: any(named: 'excludeIds'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => [payload('n-1')]);
      await notifier.fetchMore(excludeIds: const [], force: true);

      expect(notifier.canAutoFetch(), isTrue);
    });
  });
}
