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
          goal: any(named: 'goal'),
          decidedVia: any(named: 'decidedVia'),
          latencyMs: any(named: 'latencyMs'),
        )).thenAnswer((_) async {});
    when(() => analytics.trackEssentielTriageSession(
          slateSize: any(named: 'slateSize'),
          goal: any(named: 'goal'),
          goalReached: any(named: 'goalReached'),
          endedBy: any(named: 'endedBy'),
          autoFetches: any(named: 'autoFetches'),
          kept: any(named: 'kept'),
          later: any(named: 'later'),
          passed: any(named: 'passed'),
          durationMs: any(named: 'durationMs'),
        )).thenAnswer((_) async {});
    when(() => analytics.trackEssentielTriageStopNudge(
          action: any(named: 'action'),
          consecutivePass: any(named: 'consecutivePass'),
          keptCount: any(named: 'keptCount'),
          goal: any(named: 'goal'),
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
    test('le gel prend TOUT le pool, jamais une coupe à la cible', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);

      final state = c.read(essentielTriageProvider);
      expect(
        state.slate,
        [for (var i = 0; i < 8; i++) 'p$i'],
        reason: 'la cible borne les gardés, plus la taille du slate',
      );
      expect(state.effectiveGoal, kTriageGoalDefault);
    });

    test('syncSlate fige l\'ordre au premier appel', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.syncSlate(_slate);

      expect(c.read(essentielTriageProvider).slate, _slate);
      expect(c.read(essentielTriageProvider).isActive, isTrue);
    });

    test('syncSlate append en queue sans réordonner le préfixe', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

      notifier.syncSlate(const ['c', 'a', 'x', 'b', 'y']);

      expect(c.read(essentielTriageProvider).slate, [..._slate, 'x', 'y']);
    });

    test('syncSlate est rejouable sans doublon', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);
      notifier.syncSlate(const [..._slate, 'x']);
      final before = c.read(essentielTriageProvider);

      notifier.syncSlate(const [..._slate, 'x']);

      expect(identical(c.read(essentielTriageProvider), before), isTrue);
    });

    test('syncSlate dédupe un pool qui porte deux fois le même id', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.syncSlate(const ['a', 'b', 'a', 'c']);

      expect(c.read(essentielTriageProvider).slate, _slate);
    });

    test('un slate épuisé rouvre quand le pool s\'allonge', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);
      for (var i = 0; i < _slate.length; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }
      expect(c.read(essentielTriageProvider).done, isTrue);

      notifier.syncSlate(const [..._slate, 'x']);

      final state = c.read(essentielTriageProvider);
      expect(state.done, isFalse);
      expect(state.currentContentId, 'x');
    });

    test(
      'un refetch qui réordonne ne change PAS le slate en cours de tri',
      () async {
        // C'est le piège n°3 : `GET /api/essentiel` re-ranke à chaque requête.
        // Sans ce gel, la pile changerait sous le doigt et la barre de
        // progression mentirait.
        final c = makeContainer();
        final notifier = await hydrated(c);
        notifier.syncSlate(_slate);

        notifier.syncSlate(const ['c', 'b', 'a']);

        expect(c.read(essentielTriageProvider).slate, _slate);
      },
    );

    test('un slate vide ne démarre pas le tri', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.syncSlate(const []);

      expect(c.read(essentielTriageProvider).hasStarted, isFalse);
      expect(c.read(essentielTriageProvider).isActive, isFalse);
    });
  });

  group('décisions', () {
    test('avance dans la pile et enregistre le rang du slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      final state = c.read(essentielTriageProvider);
      expect(state.decisions['a']!.rank, 1);
      expect(state.currentContentId, 'b');
      expect(state.keptContentIds, ['a']);
    });

    test('later compte comme gardé, pass non', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

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
      notifier.syncSlate(_slate);

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
      notifier.syncSlate(_slate);
      for (var i = 0; i < _slate.length; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }

      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      expect(c.read(essentielTriageProvider).decisions.length, 3);
    });

    test('les gardés restent dans l\'ordre du slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

      notifier.decide(TriageDecision.pass, via: TriageVia.swipe); // a
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe); // b
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe); // c

      expect(c.read(essentielTriageProvider).keptContentIds, ['b', 'c']);
    });

    test('le tri se termine au $kTriageGoalDefault e gardé, pas avant',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);

      for (var i = 0; i < kTriageGoalDefault - 1; i++) {
        notifier.decide(TriageDecision.keep, via: TriageVia.swipe);
        expect(c.read(essentielTriageProvider).done, isFalse,
            reason: 'seulement ${i + 1} gardés');
      }
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      final state = c.read(essentielTriageProvider);
      expect(state.goalReached, isTrue);
      expect(state.done, isTrue);
      expect(state.poolExhausted, isFalse,
          reason: 'il restait 3 articles : c\'est bien la cible qui a fini');
    });

    test('un refus ne rapproche pas de la cible', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);

      for (var i = 0; i < 6; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }

      expect(c.read(essentielTriageProvider).done, isFalse);
      expect(c.read(essentielTriageProvider).keptCount, 0);
    });

    test('« Plus tard » fait avancer la cible comme « Je garde »', () async {
      // Non-régression de la décision PO : mettre de côté est un choix
      // positif, il compte donc dans l'objectif du jour.
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);
      notifier.setGoal(3);

      notifier.decide(TriageDecision.later, via: TriageVia.button);
      notifier.decide(TriageDecision.later, via: TriageVia.button);
      expect(c.read(essentielTriageProvider).done, isFalse);
      notifier.decide(TriageDecision.later, via: TriageVia.button);

      expect(c.read(essentielTriageProvider).goalReached, isTrue);
      expect(c.read(essentielTriageProvider).done, isTrue);
    });

    test('l\'auto-keep lecture compte comme un gardé ordinaire', () async {
      // Non-régression 33.2 : `decide(keep, via: read)` doit faire avancer la
      // cible exactement comme un keep au swipe.
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);
      notifier.setGoal(3);

      notifier.decide(TriageDecision.keep, via: TriageVia.read);
      notifier.decide(TriageDecision.keep, via: TriageVia.read);
      notifier.decide(TriageDecision.keep, via: TriageVia.read);

      final state = c.read(essentielTriageProvider);
      expect(state.keptCount, 3);
      expect(state.done, isTrue);
    });
  });

  group('nudge d\'arrêt (consecutivePassCount)', () {
    test('$kTriageStopNudgeThreshold refus enchaînés déclenchent le seuil',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);

      for (var i = 0; i < kTriageStopNudgeThreshold; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }

      expect(c.read(essentielTriageProvider).consecutivePassCount,
          kTriageStopNudgeThreshold);
    });

    test('un gardé intercalé remet le compteur à zéro', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);
      for (var i = 0; i < 4; i++) {
        notifier.decide(TriageDecision.pass, via: TriageVia.swipe);
      }

      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      expect(c.read(essentielTriageProvider).consecutivePassCount, 0);
    });

    test('le compteur survit à l\'hydratation (aucun champ persisté)',
        () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);
      for (var i = 0; i < kTriageStopNudgeThreshold; i++) {
        n1.decide(TriageDecision.pass, via: TriageVia.swipe);
      }
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      expect(c2.read(essentielTriageProvider).consecutivePassCount,
          kTriageStopNudgeThreshold);
    });

    test('stopTriage termine le tri sur les gardés obtenus', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 8; i++) 'p$i']);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      notifier.stopTriage();

      final state = c.read(essentielTriageProvider);
      expect(state.stopped, isTrue);
      expect(state.done, isTrue);
      expect(state.keptCount, 1);
      expect(state.goalReached, isFalse,
          reason: 'arrêter n\'est pas atteindre la cible — et ce n\'est pas '
              'un échec non plus : la fin de tri n\'affiche plus l\'objectif');
      verify(() => analytics.trackEssentielTriageStopNudge(
            action: 'accepted',
            consecutivePass: any(named: 'consecutivePass'),
            keptCount: 1,
            goal: kTriageGoalDefault,
          )).called(1);
    });

    test('dismissStopNudge est persisté (pas de réapparition au remontage)',
        () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.syncSlate(_slate);
      n1.dismissStopNudge();
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      expect(c2.read(essentielTriageProvider).stopNudgeDismissed, isTrue);
    });

    test('restart lève l\'arrêt et rouvre le nudge', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);
      notifier.dismissStopNudge();
      notifier.stopTriage();

      notifier.restart();

      final state = c.read(essentielTriageProvider);
      expect(state.stopped, isFalse);
      expect(state.stopNudgeDismissed, isFalse);
      expect(state.isActive, isTrue);
    });
  });

  group('persistance du jour', () {
    test('le tri partiel survit à un cold-boot', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.syncSlate(_slate);
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
      notifier.syncSlate(_slate);
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

  group('« Refaire ? »', () {
    test('remet les décisions à zéro sans rebattre le slate', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);
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

  group('objectif de gardés (setGoal / extendGoal)', () {
    /// Pool du jour : le slate de 3 suivi de deux articles de carrousel.
    const pool = [..._slate, 'x', 'y'];

    test('la cible par défaut vaut $kTriageGoalDefault', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(pool);

      expect(c.read(essentielTriageProvider).goal, isNull);
      expect(c.read(essentielTriageProvider).effectiveGoal,
          kTriageGoalDefault);
    });

    test('setGoal ne retire JAMAIS un id du slate', () async {
      // Tout l'intérêt de la 33.4 : baisser la cible ne détruit plus rien,
      // donc la contrainte « ne jamais perdre une décision » devient
      // structurellement impossible à violer.
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(pool);

      notifier.setGoal(kTriageGoalMin);

      expect(c.read(essentielTriageProvider).slate, pool);
    });

    test('setGoal en deçà des gardés termine le tri dans la frame', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(pool);
      for (var i = 0; i < 4; i++) {
        notifier.decide(TriageDecision.keep, via: TriageVia.swipe);
      }
      expect(c.read(essentielTriageProvider).done, isFalse);

      notifier.setGoal(3); // « finalement 3 me suffisent »

      expect(c.read(essentielTriageProvider).done, isTrue);
      expect(c.read(essentielTriageProvider).keptCount, 4);
    });

    test('bornes du stepper : [$kTriageGoalMin, $kTriageGoalMax]', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(pool);

      notifier.setGoal(1);
      expect(c.read(essentielTriageProvider).effectiveGoal, kTriageGoalMin);

      notifier.setGoal(99);
      expect(c.read(essentielTriageProvider).effectiveGoal, kTriageGoalMax);
    });

    test('setGoal marche même sans tri commencé', () async {
      // Le réglage ne dépend plus du pool : le clamper sur l'existence d'un
      // slate n'aurait plus de sens.
      final c = makeContainer();
      final notifier = await hydrated(c);

      notifier.setGoal(7);

      expect(c.read(essentielTriageProvider).effectiveGoal, 7);
    });

    test('extendGoal dépasse le plafond du stepper et rouvre la pile',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate([for (var i = 0; i < 12; i++) 'p$i']);
      notifier.setGoal(kTriageGoalMax);
      for (var i = 0; i < kTriageGoalMax; i++) {
        notifier.decide(TriageDecision.keep, via: TriageVia.swipe);
      }
      expect(c.read(essentielTriageProvider).done, isTrue);

      notifier.extendGoal(kTriageGoalExtendStep);

      final state = c.read(essentielTriageProvider);
      expect(state.effectiveGoal, kTriageGoalMax + kTriageGoalExtendStep);
      expect(state.done, isFalse, reason: 'la pile rouvre');
      expect(state.isActive, isTrue);
      expect(state.currentContentId, 'p10');
    });

    test('extendGoal lève un arrêt volontaire', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(pool);
      notifier.stopTriage();
      expect(c.read(essentielTriageProvider).done, isTrue);

      notifier.extendGoal(kTriageGoalExtendStep);

      expect(c.read(essentielTriageProvider).stopped, isFalse);
      expect(c.read(essentielTriageProvider).isActive, isTrue);
    });

    test('la cible survit à un cold-boot', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.syncSlate(_slate);
      n1.setGoal(8);
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      expect(c2.read(essentielTriageProvider).goal, 8);
      expect(c2.read(essentielTriageProvider).slate, _slate,
          reason: 'la cible ne touche pas au slate');
    });
  });

  group('migration du blob jour (v1 → v2)', () {
    test('un blob v1 est ignoré, pas réinterprété comme un objectif', () async {
      // `target` v1 = **taille de slate**. Le relire tel quel donnerait
      // « garde 7 articles » à qui avait demandé une pile de 7.
      SharedPreferences.setMockInitialValues({
        '$kTriageLegacyPrefsKeyPrefix${todayKey()}': jsonEncode({
          'day_key': todayKey(),
          'slate': _slate,
          'decisions': const <Map<String, dynamic>>[],
          'target': 7,
        }),
      });

      final c = makeContainer();
      await hydrated(c);

      final state = c.read(essentielTriageProvider);
      expect(state.hasStarted, isFalse);
      expect(state.goal, isNull);
      expect(state.effectiveGoal, kTriageGoalDefault);
    });

    test('les clés v1 sont purgées, y compris celle du jour', () async {
      SharedPreferences.setMockInitialValues({
        '$kTriageLegacyPrefsKeyPrefix${todayKey()}': '{}',
        '${kTriageLegacyPrefsKeyPrefix}2020-01-01': '{}',
      });

      final c = makeContainer();
      await hydrated(c);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getKeys().where((k) => k.startsWith(kTriageLegacyPrefsKeyPrefix)),
        isEmpty,
      );
    });

    test('un blob v2 est relu à l\'identique', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.syncSlate(_slate);
      n1.setGoal(4);
      n1.decide(TriageDecision.keep, via: TriageVia.swipe);
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      final state = c2.read(essentielTriageProvider);
      expect(state.slate, _slate);
      expect(state.goal, 4);
      expect(state.keptContentIds, ['a']);
    });
  });

  group('lecture depuis la pile (TriageVia.read)', () {
    test('keep via read est enregistré et sérialisé decided_via=read',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

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
      notifier.syncSlate(const [..._slate, 'x']);
      expect(c.read(essentielTriageProvider).slate, [..._slate, 'x']);

      notifier.pruneUnavailable(_slate.toSet());

      final state = c.read(essentielTriageProvider);
      expect(state.slate, _slate);
      expect(state.currentContentId, 'a', reason: 'le tri reprend son cours');
    });

    test('garde les ids déjà décidés, même absents du pool', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);
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
      notifier.syncSlate(_slate);
      final before = c.read(essentielTriageProvider);

      notifier.pruneUnavailable({..._slate, 'z'});

      expect(identical(c.read(essentielTriageProvider), before), isTrue);
    });

    test('un pool vide est un no-op (jamais de purge sur une carte vide)',
        () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

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
      notifier.syncSlate(const ['vieux-1', 'vieux-2']);

      notifier.pruneUnavailable(_slate.toSet());
      expect(c.read(essentielTriageProvider).hasStarted, isFalse);

      // La carte re-gèle alors sur les articles du jour, sans intervention.
      notifier.syncSlate(_slate);
      expect(c.read(essentielTriageProvider).slate, _slate);
    });

    test('la réparation survit à un cold-boot', () async {
      final c1 = makeContainer();
      final n1 = await hydrated(c1);
      n1.syncSlate(const [..._slate, 'x']);
      n1.pruneUnavailable(_slate.toSet());
      await Future<void>.delayed(Duration.zero);

      final c2 = makeContainer();
      await hydrated(c2);

      expect(c2.read(essentielTriageProvider).slate, _slate);
    });

    test('prune puis syncSlate ne se contredisent pas : le pool revient par '
        'émissions partielles', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      const fullPool = ['a', 'b', 'c', 'x', 'y', 'z'];

      notifier.syncSlate(fullPool);
      expect(c.read(essentielTriageProvider).slate, fullPool);

      // Premier rendu du cold-boot : seul le héros est disponible.
      notifier.pruneUnavailable(_slate.toSet());
      expect(c.read(essentielTriageProvider).slate, _slate);

      // Le carrousel revient en plusieurs émissions : chacune n'allonge que la
      // queue, jamais ne rebat le préfixe. `pruneUnavailable` ne retire que des
      // ids **absents** du pool et `syncSlate` n'append que des ids
      // **présents** : les deux ne peuvent pas boucler l'un contre l'autre.
      notifier.syncSlate(const ['a', 'b', 'c', 'x']);
      expect(c.read(essentielTriageProvider).slate, ['a', 'b', 'c', 'x']);

      notifier.syncSlate(fullPool);
      expect(c.read(essentielTriageProvider).slate, fullPool);
    });
  });

  group('envoi batché', () {
    test('la fin du tri flushe toutes les décisions en un batch', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

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
      notifier.syncSlate(_slate);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      await notifier.flush();

      expect(notifier.pendingForTest.keys, contains('a'),
          reason: 'une décision perdue est une ligne manquante dans la jauge');
    });

    test('un envoi réussi vide la file d\'attente', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);
      notifier.decide(TriageDecision.keep, via: TriageVia.swipe);

      await notifier.flush();

      expect(notifier.pendingForTest, isEmpty);
    });

    test('flush sans rien en attente n\'appelle pas le réseau', () async {
      final c = makeContainer();
      final notifier = await hydrated(c);
      notifier.syncSlate(_slate);

      await notifier.flush();

      verifyNever(() => repo.postTriage(
            digestDate: any(named: 'digestDate'),
            slateSize: any(named: 'slateSize'),
            decisions: any(named: 'decisions'),
          ));
    });
  });
}
