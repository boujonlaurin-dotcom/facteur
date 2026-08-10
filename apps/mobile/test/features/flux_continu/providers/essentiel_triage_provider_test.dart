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
    test('le gel prend la cible par défaut : min(5, pool)', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.startIfNeeded([for (var i = 0; i < 8; i++) 'p$i']);

      expect(
        c.read(essentielTriageProvider).slate,
        ['p0', 'p1', 'p2', 'p3', 'p4'],
        reason: 'cible par défaut $kTriageTargetDefault, ordre du pool',
      );
    });

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
      expect(state.slate, _slate,
          reason: 'le slate reste figé pour la journée');
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

  group('cible du jour (setTarget)', () {
    /// Pool du jour : le slate de 3 suivi de deux articles de carrousel.
    const pool = [..._slate, 'x', 'y'];

    test('en hausse : append des ids du pool absents du slate, la pile rouvre',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      for (var i = 0; i < _slate.length; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }
      expect(c.read(essentielTriageProvider).done, isTrue);

      notifier.setTarget(5, pool);

      final state = c.read(essentielTriageProvider);
      expect(state.slate, pool);
      expect(state.target, 5);
      expect(state.done, isFalse, reason: 'la pile rouvre');
      expect(state.isActive, isTrue);
      expect(state.currentContentId, 'x');
    });

    test('en baisse : ne retire que des non décidés, en fin de slate',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(pool); // slate = a, b, c, x, y (cible défaut 5)
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe); // a
      notifier.decide(TriageDecision.pass, via: TriageVia.swipe); // b

      notifier.setTarget(3, pool);

      final state = c.read(essentielTriageProvider);
      expect(state.slate, _slate, reason: 'y puis x retirés, jamais a ni b');
      expect(state.target, 3);
      expect(state.decisions.keys, containsAll(<String>['a', 'b']));
      expect(state.currentContentId, 'c');
    });

    test('en baisse : s\'arrête sur un décidé — jamais de décision perdue',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(pool);
      for (var i = 0; i < pool.length; i++) {
        notifier.decide(TriageDecision.keep, via: TriageVia.swipe);
      }

      notifier.setTarget(3, pool);

      final state = c.read(essentielTriageProvider);
      expect(state.slate, pool, reason: 'tout est décidé : rien n\'est retiré');
      expect(state.target, 5,
          reason: 'la cible publiée est la taille réelle, pas le n demandé');
      expect(state.decisions.length, 5);
    });

    test('bornes : plancher $kTriageTargetMin, plafond = pool', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(pool);

      notifier.setTarget(1, pool);
      expect(c.read(essentielTriageProvider).slate.length, kTriageTargetMin);

      notifier.setTarget(99, pool);
      expect(c.read(essentielTriageProvider).slate, pool);
    });

    test('n\'ajoute pas un id déjà présent dans le slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.setTarget(4, const ['a', 'x', 'b', 'c']);

      expect(c.read(essentielTriageProvider).slate, [..._slate, 'x']);
    });

    test('sans tri commencé est un no-op', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.setTarget(5, pool);

      expect(c.read(essentielTriageProvider).hasStarted, isFalse);
    });

    test('la cible et les ajouts survivent à un cold-boot', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.startIfNeeded(_slate);
      n1.setTarget(5, pool);
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      final state = c2.read(essentielTriageProvider);
      expect(state.slate, pool);
      expect(state.target, 5);
    });
  });

  group('lecture depuis la pile (TriageVia.read)', () {
    test('keep via read est enregistré et sérialisé decided_via=read',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.decide(TriageDecision.keep, via: TriageVia.read);

      final entry = c.read(essentielTriageProvider).decisions['a']!;
      expect(entry.via, TriageVia.read);
      expect(entry.toJson()['decided_via'], 'read');
      expect(c.read(essentielTriageProvider).keptContentIds, ['a']);
    });

    test('la modalité read survit au round-trip JSON', () {
      final entry = TriageEntry.fromJson(const {
        'content_id': 'a',
        'decision': 'keep',
        'rank': 1,
        'decided_via': 'read',
      });
      expect(entry!.via, TriageVia.read);
    });
  });

  // Réparation d'un slate qui a survécu aux articles qu'il désigne. C'est ce
  // qui figeait la carte sur un corps vide (défaut E2E « aucun squelette
  // pendant le chargement » : l'aplat n'était pas une attente mais un état
  // cassé, typiquement un `extendSlate` d'hier dont le carrousel n'est pas
  // rejoué à l'hydratation depuis le cache).
  group('réparation du slate (pruneUnavailable)', () {
    test('retire les ids non décidés absents du pool', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      notifier.setTarget(4, const [..._slate, 'x']);
      expect(c.read(essentielTriageProvider).slate, [..._slate, 'x']);

      notifier.pruneUnavailable(_slate.toSet());

      final state = c.read(essentielTriageProvider);
      expect(state.slate, _slate);
      expect(state.currentContentId, 'a', reason: 'le tri reprend son cours');
    });

    test('garde les ids déjà décidés, même absents du pool', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe); // 'a'

      notifier.pruneUnavailable(const {'b', 'c'});

      final state = c.read(essentielTriageProvider);
      expect(state.slate, _slate,
          reason: 'la décision sur « a » reste comptée');
      expect(state.keptContentIds, ['a']);
    });

    test('un pool complet est un no-op', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);
      final before = c.read(essentielTriageProvider);

      notifier.pruneUnavailable({..._slate, 'z'});

      expect(identical(c.read(essentielTriageProvider), before), isTrue);
    });

    test('un pool vide est un no-op (jamais de purge sur une carte vide)',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(_slate);

      notifier.pruneUnavailable(const {});

      expect(c.read(essentielTriageProvider).slate, _slate);
    });

    test('sans tri commencé est un no-op', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.pruneUnavailable(const {'a'});

      expect(c.read(essentielTriageProvider).slate, isEmpty);
    });

    test('un slate entièrement introuvable se vide et se re-gèle', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.startIfNeeded(const ['vieux-1', 'vieux-2']);

      notifier.pruneUnavailable(_slate.toSet());
      expect(c.read(essentielTriageProvider).hasStarted, isFalse);

      // La carte re-gèle alors sur les articles du jour, sans intervention.
      notifier.startIfNeeded(_slate);
      expect(c.read(essentielTriageProvider).slate, _slate);
    });

    test('la réparation survit à un cold-boot', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.startIfNeeded(_slate);
      n1.setTarget(4, const [..._slate, 'x']);
      n1.pruneUnavailable(_slate.toSet());
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      expect(c2.read(essentielTriageProvider).slate, _slate);
    });

    test(
        'une cible étendue est restaurée quand le carrousel revient après le '
        'prune du cold-boot', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      const fullPool = ['a', 'b', 'c', 'x', 'y', 'z'];

      notifier.startIfNeeded(_slate);
      notifier.setTarget(6, fullPool);
      expect(c.read(essentielTriageProvider).target, 6);

      // Premier rendu du cold-boot : seul le héros est disponible.
      notifier.pruneUnavailable(_slate.toSet());
      expect(c.read(essentielTriageProvider).slate, _slate);
      expect(c.read(essentielTriageProvider).target, 6,
          reason: 'la préférence ne doit pas être écrasée par un pool partiel');

      // Le carrousel peut revenir en plusieurs émissions partielles : aucune
      // ne doit rabattre silencieusement la préférence de 6 à sa propre taille.
      notifier.startIfNeeded(const ['a', 'b', 'c', 'x']);
      expect(c.read(essentielTriageProvider).slate, ['a', 'b', 'c', 'x']);
      expect(c.read(essentielTriageProvider).target, 6);

      // Le pool complet arrive ensuite. `startIfNeeded` ne rebat pas le
      // préfixe, mais complète le slate jusqu'à la cible persistée.
      notifier.startIfNeeded(fullPool);
      expect(c.read(essentielTriageProvider).slate, fullPool);
      expect(c.read(essentielTriageProvider).target, 6);
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
