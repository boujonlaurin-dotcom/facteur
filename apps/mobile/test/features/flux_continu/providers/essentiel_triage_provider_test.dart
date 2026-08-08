import 'dart:convert';

import 'package:facteur/core/providers/analytics_provider.dart';
import 'package:facteur/core/services/analytics_service.dart';
import 'package:facteur/features/flux_continu/providers/essentiel_triage_provider.dart';
import 'package:facteur/features/flux_continu/repositories/essentiel_repository.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockEssentielRepository extends Mock implements EssentielRepository {}

class _MockAnalytics extends Mock implements AnalyticsService {}

/// Slate de test : 3 articles.
const _slate = ['a', 'b', 'c'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockEssentielRepository repo;
  late _MockAnalytics analytics;

  String todayKey() => TourneeProgressService.dayKey(DateTime.now());

  setUpAll(() {
    registerFallbackValue(<Map<String, dynamic>>[]);
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    repo = _MockEssentielRepository();
    analytics = _MockAnalytics();
    when(() => repo.postTriage(
          digestDate: any(named: 'digestDate'),
          slateSize: any(named: 'slateSize'),
          decisions: any(named: 'decisions'),
        )).thenAnswer((_) async => true);
    when(() => analytics.trackEssentielTriage(
          decision: any(named: 'decision'),
          contentId: any(named: 'contentId'),
          rank: any(named: 'rank'),
          slateSize: any(named: 'slateSize'),
          decidedVia: any(named: 'decidedVia'),
          latencyMs: any(named: 'latencyMs'),
        )).thenAnswer((_) async {});
    when(() => analytics.trackEssentielTriageSession(
          slateSize: any(named: 'slateSize'),
          kept: any(named: 'kept'),
          later: any(named: 'later'),
          passed: any(named: 'passed'),
          durationMs: any(named: 'durationMs'),
        )).thenAnswer((_) async {});
  });

  ProviderContainer makeContainer() {
    final container = ProviderContainer(overrides: [
      essentielRepositoryProvider.overrideWithValue(repo),
      analyticsServiceProvider.overrideWithValue(analytics),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  /// Attend la fin de l'hydratation asynchrone (SharedPreferences).
  Future<EssentielTriageNotifier> hydrated(ProviderContainer c) async {
    final notifier = c.read(essentielTriageProvider.notifier);
    while (!c.read(essentielTriageProvider).hydrated) {
      await Future<void>.delayed(Duration.zero);
    }
    return notifier;
  }

  group('slate figé', () {
    test('startIfNeeded fige l\'ordre au premier appel', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.startIfNeeded(_slate);

      expect(c.read(essentielTriageProvider).slate, _slate);
      expect(c.read(essentielTriageProvider).isActive, isTrue);
    });

    test(
      'un refetch qui réordonne ne change PAS le slate en cours de tri',
      () async {
        // C'est le piège n°3 : `GET /api/essentiel` re-ranke à chaque requête.
        // Sans ce gel, la pile changerait sous le doigt et la barre de
        // progression mentirait.
        final c = makeContainer();
        final notifier = await hydrated(c);
        notifier.startIfNeeded(_slate);

        notifier.startIfNeeded(const ['c', 'b', 'a']);

        expect(c.read(essentielTriageProvider).slate, _slate);
      },
    );

    test('un slate vide ne démarre pas le tri', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.startIfNeeded(const []);

      expect(c.read(essentielTriageProvider).hasStarted, isFalse);
      expect(c.read(essentielTriageProvider).isActive, isFalse);
    });
  });

  group('décisions', () {
    test('avance dans la pile et enregistre le rang du slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      final state = c.read(essentielTriageProvider);
      expect(state.decisions['a']!.rank, 1);
      expect(state.currentContentId, 'b');
      expect(state.keptContentIds, ['a']);
    });

    test('later compte comme gardé, pass non', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.decide(TriageDecision.later, via: TriageVia.button);
      notifier.decide(TriageDecision.pass, via: TriageVia.swipe);

      final state = c.read(essentielTriageProvider);
      expect(state.keptContentIds, ['a']);
      expect(state.keptCount, 1);
      expect(state.laterCount, 1);
      expect(state.passedCount, 1);
    });

    test('le tri fini quitte l\'état actif', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      for (var i = 0; i < _slate.length; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }

      final state = c.read(essentielTriageProvider);
      expect(state.done, isTrue);
      expect(state.isActive, isFalse);
    });

    test('décider au-delà du slate est un no-op', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      for (var i = 0; i < _slate.length; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }

      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      expect(c.read(essentielTriageProvider).decisions.length, 3);
    });

    test('les gardés restent dans l\'ordre du slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.decide(TriageDecision.pass, via: TriageVia.swipe); // a
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe); // b
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe); // c

      expect(c.read(essentielTriageProvider).keptContentIds, ['b', 'c']);
    });
  });

  group('persistance du jour', () {
    test('le tri partiel survit à un cold-boot', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.startIfNeeded(_slate);
      n1.decide(TriageDecision.keep, via: TriageVia.swipe);
      // Laisse la persistance asynchrone se poser.
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      final state = c2.read(essentielTriageProvider);
      expect(state.slate, _slate);
      expect(state.decisions.containsKey('a'), isTrue);
      expect(state.currentContentId, 'b');
      expect(state.isActive, isTrue);
    });

    test('les clés des jours précédents sont purgées au boot', () async {
      SharedPreferences.setMockInitialValues({
        '${kTriagePrefsKeyPrefix}2020-01-01': jsonEncode({
          'day_key': '2020-01-01',
          'slate': _slate,
          'decisions': const <Map<String, dynamic>>[],
        }),
      });

      final c = makeContainer();
      await hydrated(c);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getKeys().where((k) => k.startsWith(kTriagePrefsKeyPrefix)),
          isNot(contains('${kTriagePrefsKeyPrefix}2020-01-01')));
    });

    test('la clé du jour porte le dayKey courant', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      await Future<void>.delayed(Duration.zero);

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(triagePrefsKey(todayKey())), isNotNull);
    });

    test('un blob corrompu ne bloque pas l\'hydratation', () async {
      SharedPreferences.setMockInitialValues({
        triagePrefsKey(TourneeProgressService.dayKey(DateTime.now())):
            'pas du json',
      });

      final c = makeContainer();
      await hydrated(c);

      expect(c.read(essentielTriageProvider).hydrated, isTrue);
      expect(c.read(essentielTriageProvider).hasStarted, isFalse);
    });
  });

  group('« Trier à nouveau »', () {
    test('remet les décisions à zéro sans rebattre le slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);
      notifier.decide(TriageDecision.pass, via: TriageVia.swipe);

      notifier.restart();

      final state = c.read(essentielTriageProvider);
      expect(state.decisions, isEmpty);
      expect(state.slate, _slate, reason: 'le slate reste figé pour la journée');
      expect(state.currentContentId, 'a');
      expect(state.isActive, isTrue);
    });

    test('restart sans tri commencé est un no-op', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.restart();

      expect(c.read(essentielTriageProvider).hasStarted, isFalse);
    });
  });

  group('« Voir d\'autres articles » (extendSlate)', () {
    test('ajoute des ids au slate figé et rouvre la pile', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      for (var i = 0; i < _slate.length; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }
      expect(c.read(essentielTriageProvider).done, isTrue);

      notifier.extendSlate(const ['x', 'y']);

      final state = c.read(essentielTriageProvider);
      expect(state.slate, [..._slate, 'x', 'y']);
      expect(state.done, isFalse, reason: 'la pile rouvre');
      expect(state.isActive, isTrue);
      expect(state.currentContentId, 'x');
    });

    test('n\'ajoute pas un id déjà présent dans le slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.extendSlate(const ['a', 'x', 'b']); // a, b déjà présents

      expect(c.read(essentielTriageProvider).slate, [..._slate, 'x']);
    });

    test('borne les ajouts à kTriageExtendMax', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.extendSlate(List.generate(kTriageExtendMax + 3, (i) => 'x$i'));

      final added =
          c.read(essentielTriageProvider).slate.length - _slate.length;
      expect(added, kTriageExtendMax);
    });

    test('ne touche pas aux décisions déjà prises', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe); // a
      notifier.decide(TriageDecision.pass, via: TriageVia.swipe); // b
      notifier.decide(TriageDecision.pass, via: TriageVia.swipe); // c

      notifier.extendSlate(const ['x']);

      final state = c.read(essentielTriageProvider);
      expect(state.decisions.keys, containsAll(<String>['a', 'b', 'c']));
      expect(state.keptContentIds, ['a']);
      expect(state.currentContentId, 'x');
    });

    test('sans tri commencé est un no-op', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.extendSlate(const ['x']);

      expect(c.read(essentielTriageProvider).hasStarted, isFalse);
    });

    test('un ajout sans rien de neuf ne change pas l\'état', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.extendSlate(const ['a', 'b']); // tous déjà présents

      expect(c.read(essentielTriageProvider).slate, _slate);
    });

    test('les ajouts survivent à un cold-boot', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.startIfNeeded(_slate);
      n1.extendSlate(const ['x', 'y']);
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      expect(c2.read(essentielTriageProvider).slate, [..._slate, 'x', 'y']);
    });
  });

  group('envoi batché', () {
    test('la fin du tri flushe toutes les décisions en un batch', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      for (var i = 0; i < _slate.length; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }
      await Future<void>.delayed(Duration.zero);

      final captured = verify(() => repo.postTriage(
            digestDate: captureAny(named: 'digestDate'),
            slateSize: captureAny(named: 'slateSize'),
            decisions: captureAny(named: 'decisions'),
          )).captured;
      expect(captured, isNotEmpty);
      final decisions = captured.last as List<Map<String, dynamic>>;
      expect(decisions.length, 3);
      expect(decisions.first['decision'], 'pass');
      expect(decisions.first['rank'], 1);
    });

    test('un échec réseau garde les décisions en attente', () async {
      when(() => repo.postTriage(
            digestDate: any(named: 'digestDate'),
            slateSize: any(named: 'slateSize'),
            decisions: any(named: 'decisions'),
          )).thenAnswer((_) async => false);

      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      await notifier.flush();

      expect(notifier.pendingForTest.keys, contains('a'),
          reason: 'une décision perdue est une ligne manquante dans la jauge');
    });

    test('un envoi réussi vide la file d\'attente', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      await notifier.flush();

      expect(notifier.pendingForTest, isEmpty);
    });

    test('flush sans rien en attente n\'appelle pas le réseau', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      await notifier.flush();

      verifyNever(() => repo.postTriage(
            digestDate: any(named: 'digestDate'),
            slateSize: any(named: 'slateSize'),
            decisions: any(named: 'decisions'),
          ));
    });
  });
}
