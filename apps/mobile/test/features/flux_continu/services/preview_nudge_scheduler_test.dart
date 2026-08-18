import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/flux_continu/services/preview_nudge_scheduler.dart';
import 'package:facteur/features/flux_continu/services/tournee_progress_service.dart';

/// Ce que ces tests gardent : un nudge d'apprentissage ne doit se faire
/// remarquer qu'un nombre borné de fois, et plus jamais dès que l'utilisateur a
/// fait le geste — sinon l'indice devient du bruit sur une surface qu'on
/// regarde tous les matins. Deux réglages de la même mécanique : le pulse
/// auto-grow du flux (3/jour, espacés) et le nudge de la pile de tri (1/jour de
/// Tournée, sans espacement).
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;

  PreviewNudgeScheduler buildAutoGrow() => PreviewNudgeScheduler(
        countKeyPrefix: kAutoGrowCountPrefixPrefsKey,
        lastTriggerKey: kAutoGrowLastTriggerPrefsKey,
        discoveredKey: kAutoGrowDiscoveredPrefsKey,
        clock: () => now,
        prefs: SharedPreferences.getInstance,
      );

  PreviewNudgeScheduler buildTriage() => PreviewNudgeScheduler(
        countKeyPrefix: kTriagePreviewCountPrefixPrefsKey,
        lastTriggerKey: kTriagePreviewLastTriggerPrefsKey,
        discoveredKey: kTriagePreviewDiscoveredPrefsKey,
        clock: () => now,
        prefs: SharedPreferences.getInstance,
        dayKey: TourneeProgressService.dayKey,
        dailyBudget: 1,
        minSpacing: Duration.zero,
      );

  PreviewNudgeScheduler buildArticleSwipe() => PreviewNudgeScheduler(
        countKeyPrefix: kArticleSwipeCountPrefixPrefsKey,
        lastTriggerKey: kArticleSwipeLastTriggerPrefsKey,
        discoveredKey: kArticleSwipeDiscoveredPrefsKey,
        clock: () => now,
        prefs: SharedPreferences.getInstance,
        dailyBudget: 2,
        minSpacing: const Duration(hours: 2),
        postDiscoverySpacing: kArticleSwipePostDiscoverySpacing,
        postDiscoveryBudget: kArticleSwipePostDiscoveryBudget,
      );

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    now = DateTime(2026, 7, 18, 9);
  });

  group('pulse auto-grow (flux)', () {
    test('autorise un pulse dans l\'état initial', () async {
      expect(await buildAutoGrow().canTriggerNow(), isTrue);
    });

    test('refuse tant que l\'espacement minimum n\'est pas écoulé', () async {
      final s = buildAutoGrow();
      await s.recordTriggered();

      // Juste après → bloqué par l'espacement.
      expect(await s.canTriggerNow(), isFalse);

      // +89 min → toujours bloqué ; +90 min → autorisé de nouveau.
      now = now.add(const Duration(minutes: 89));
      expect(await s.canTriggerNow(), isFalse);
      now = now.add(const Duration(minutes: 1));
      expect(await s.canTriggerNow(), isTrue);
    });

    test('plafonne à $kAutoGrowDailyBudget pulses par jour', () async {
      final s = buildAutoGrow();
      for (var i = 0; i < kAutoGrowDailyBudget; i++) {
        expect(await s.canTriggerNow(), isTrue,
            reason: 'pulse #$i doit passer');
        await s.recordTriggered();
        // Avance au-delà de l'espacement pour isoler la limite de budget.
        now = now.add(kAutoGrowMinSpacing + const Duration(minutes: 1));
      }
      // Budget épuisé pour le reste de la journée, même espacement respecté.
      expect(await s.canTriggerNow(), isFalse);
    });

    test('le compteur repart à zéro au changement de jour', () async {
      final s = buildAutoGrow();
      for (var i = 0; i < kAutoGrowDailyBudget; i++) {
        await s.recordTriggered();
        now = now.add(kAutoGrowMinSpacing + const Duration(minutes: 1));
      }
      expect(await s.canTriggerNow(), isFalse);

      // Lendemain, même heure → nouvelle clé datée = budget frais.
      now = DateTime(2026, 7, 19, 9);
      expect(await s.canTriggerNow(), isTrue);
    });

    test('markDiscovered coupe définitivement le nudge', () async {
      final s = buildAutoGrow();
      expect(await s.canTriggerNow(), isTrue);

      await s.markDiscovered();
      expect(await s.canTriggerNow(), isFalse);

      // Même le lendemain, une fois découvert, plus aucun pulse.
      now = DateTime(2026, 7, 20, 9);
      expect(await s.canTriggerNow(), isFalse);
    });

    test('la découverte survit à une nouvelle instance (elle est persistée)',
        () async {
      await buildAutoGrow().markDiscovered();
      // Instance neuve → le latch mémoire ne joue pas, seul le flag persisté.
      expect(await buildAutoGrow().canTriggerNow(), isFalse);
    });
  });

  group('nudge de la pile de tri', () {
    setUp(() {
      // Bien après la bascule 07h30 : dayKey == ce jour-là.
      now = DateTime.utc(2026, 7, 18, 10);
    });

    test('autorise le nudge dans l\'état initial', () async {
      expect(await buildTriage().canTriggerNow(), isTrue);
    });

    test('une seule fois par jour', () async {
      final s = buildTriage();
      await s.recordTriggered();

      expect(await s.canTriggerNow(), isFalse);
      // Même plus tard dans la journée.
      now = now.add(const Duration(hours: 6));
      expect(await s.canTriggerNow(), isFalse);
    });

    test('reprend le lendemain', () async {
      final s = buildTriage();
      await s.recordTriggered();

      now = now.add(const Duration(days: 1));
      expect(await s.canTriggerNow(), isTrue);
    });

    test('le long-press réel éteint le nudge définitivement', () async {
      final s = buildTriage();
      await s.markDiscovered();

      expect(await s.canTriggerNow(), isFalse);
      // Le lendemain non plus : la découverte n'a pas de date d'expiration.
      now = now.add(const Duration(days: 1));
      expect(await s.canTriggerNow(), isFalse);
    });

    test('purge les clés des jours précédents', () async {
      final s = buildTriage();
      await s.recordTriggered();

      now = now.add(const Duration(days: 1));
      await s.recordTriggered();

      final prefs = await SharedPreferences.getInstance();
      final keys = prefs
          .getKeys()
          .where((k) => k.startsWith(kTriagePreviewCountPrefixPrefsKey))
          .toList();
      expect(keys, hasLength(1));
    });

    test('les deux nudges ont des compteurs indépendants', () async {
      // Le pulse du flux ne doit pas consommer le budget de la pile de tri :
      // ce sont deux apprentissages sur deux surfaces.
      await buildAutoGrow().recordTriggered();
      expect(await buildTriage().canTriggerNow(), isTrue);
    });
  });

  group('rappel du swipe d\'article (étage post-découverte)', () {
    test('le tout premier article ouvert peut rebondir', () async {
      expect(await buildArticleSwipe().canTriggerNow(), isTrue);
    });

    test('2 rappels par jour, espacés de 2 h, tant que le geste est inconnu',
        () async {
      final s = buildArticleSwipe();
      await s.recordTriggered();
      expect(await s.canTriggerNow(), isFalse);

      now = now.add(const Duration(hours: 2));
      expect(await s.canTriggerNow(), isTrue);
      await s.recordTriggered();

      // Budget du jour épuisé, même passé l'espacement.
      now = now.add(const Duration(hours: 3));
      expect(await s.canTriggerNow(), isFalse);
      // …et il repart le lendemain : on continue à montrer le geste.
      now = now.add(const Duration(days: 1));
      expect(await s.canTriggerNow(), isTrue);
    });

    test('après le premier swipe, un rappel par semaine', () async {
      final s = buildArticleSwipe();
      await s.markDiscovered();

      // Le lendemain : trop tôt, le régime est hebdomadaire désormais.
      now = now.add(const Duration(days: 1));
      expect(await s.canTriggerNow(), isFalse);

      now = now.add(const Duration(days: 6));
      expect(await s.canTriggerNow(), isTrue);
    });

    test(
        'les rappels post-découverte sont bornés à '
        '$kArticleSwipePostDiscoveryBudget', () async {
      final s = buildArticleSwipe();
      await s.markDiscovered();

      for (var i = 0; i < kArticleSwipePostDiscoveryBudget; i++) {
        now = now.add(kArticleSwipePostDiscoverySpacing);
        expect(await s.canTriggerNow(), isTrue, reason: 'rappel #$i');
        await s.recordTriggered();
      }

      // Budget de vie épuisé : plus jamais, quel que soit le temps écoulé.
      now = now.add(const Duration(days: 365));
      expect(await s.canTriggerNow(), isFalse);
    });

    test('le compteur de rappels survit au changement de jour', () async {
      // Le compteur post-découverte ne vit pas sous le préfixe daté, sinon la
      // purge quotidienne relancerait le budget chaque semaine.
      final s = buildArticleSwipe();
      await s.markDiscovered();
      now = now.add(kArticleSwipePostDiscoverySpacing);
      await s.recordTriggered();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getInt('${kArticleSwipeDiscoveredPrefsKey}_reminders'), 1);
    });

    test('les nudges d\'aperçu n\'ont pas d\'étage post-découverte', () async {
      // Non-régression : sans `postDiscoverySpacing`, la découverte éteint le
      // nudge pour de bon, comportement des deux nudges d'aperçu.
      final s = buildAutoGrow();
      await s.markDiscovered();
      now = now.add(const Duration(days: 365));
      expect(await s.canTriggerNow(), isFalse);
    });
  });
}
