import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';
import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_provider.dart'
    show notifIdHash;
import 'package:facteur/features/well_informed/data/well_informed_repository.dart';
import 'package:facteur/features/well_informed/providers/well_informed_prompt_provider.dart';

/// Fake repository — capture les appels sans toucher au réseau.
class _FakeRepository implements WellInformedRepository {
  final List<({int score, String context})> calls = [];

  @override
  Future<void> submitRating({
    required int score,
    String context = 'digest_inline',
  }) async {
    calls.add((score: score, context: context));
  }
}

/// Réplique la clé jour du provider (`yyyy-mm-dd`) pour localiser un jour qui
/// « sort » ou non sous un salt donné.
String _dayKey(DateTime d) {
  final m = d.month.toString().padLeft(2, '0');
  final day = d.day.toString().padLeft(2, '0');
  return '${d.year}-$m-$day';
}

bool _sorts(String salt, DateTime day, int percent) =>
    notifIdHash('$salt#${_dayKey(day)}') % 100 < percent;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repo;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = _FakeRepository();
    now = DateTime(2026, 4, 24, 10, 0, 0);
  });

  /// Contrôleur avec le tirage quotidien forcé à 100 % (toujours « sort ») pour
  /// isoler la logique de cooldown des tests ci-dessous.
  WellInformedPromptController build() {
    return WellInformedPromptController(
      nudgeService: NudgeService(
        storage: NudgeStorage(),
        clock: () => now,
      ),
      repository: repo,
      clock: () => now,
      prefs: SharedPreferences.getInstance,
      samplingPercent: 100,
    );
  }

  test('shouldShow true on fresh install (draw forced on)', () async {
    final c = build();
    expect(await c.shouldShow(), isTrue);
  });

  test('after submit, blocked for 60 days', () async {
    final c = build();
    await c.submit(7);

    now = now.add(const Duration(days: 59, hours: 23));
    expect(await c.shouldShow(), isFalse);

    now = now.add(const Duration(hours: 2));
    // 60j + 1h écoulés depuis submit → shouldShow true à nouveau.
    expect(await c.shouldShow(), isTrue);
  });

  test('after skip, blocked for 21 days only', () async {
    final c = build();
    await c.skip();

    now = now.add(const Duration(days: 20, hours: 23));
    expect(await c.shouldShow(), isFalse);

    now = now.add(const Duration(hours: 2));
    expect(await c.shouldShow(), isTrue);
  });

  test('submit persists the submitted timestamp', () async {
    final c = build();
    await c.submit(9);

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getInt(kWellInformedLastSubmittedPrefsKey),
      now.millisecondsSinceEpoch,
    );
  });

  test('submit calls repository with the score + context', () async {
    final c = build();
    await c.submit(6, context: 'digest_inline');
    expect(repo.calls.single.score, 6);
    expect(repo.calls.single.context, 'digest_inline');
  });

  test('skip does NOT call the repository', () async {
    final c = build();
    await c.skip();
    expect(repo.calls, isEmpty);
  });

  test('submit uses the long (60j) cooldown even after a prior skip', () async {
    final c = build();

    await c.skip();
    now = now.add(const Duration(days: 22));
    expect(await c.shouldShow(), isTrue);

    await c.submit(5);
    now = now.add(const Duration(days: 22));
    // Après submit, le cooldown long 60j domine le cooldown court du nudge.
    expect(await c.shouldShow(), isFalse);
  });

  test('uses nudge id well_informed_poll', () {
    expect(NudgeIds.wellInformedPoll, 'well_informed_poll');
  });

  group('tirage quotidien non biaisé (~15%)', () {
    const salt = 'seed-42';

    WellInformedPromptController drawBuild() {
      SharedPreferences.setMockInitialValues(<String, Object>{
        kWellInformedSamplingSaltPrefsKey: salt,
      });
      return WellInformedPromptController(
        nudgeService: NudgeService(
          storage: NudgeStorage(),
          clock: () => now,
        ),
        repository: repo,
        clock: () => now,
        prefs: SharedPreferences.getInstance,
        // samplingPercent par défaut = kWellInformedDailySamplingPercent (15).
      );
    }

    test('un jour qui « sort » affiche le sondage', () async {
      final c = drawBuild();
      final day = List.generate(60, (i) => DateTime(2026, 1, 1).add(Duration(days: i)))
          .firstWhere((d) => _sorts(salt, d, kWellInformedDailySamplingPercent));
      now = day;
      expect(await c.shouldShow(), isTrue);
    });

    test('un jour qui ne « sort » pas masque le sondage', () async {
      final c = drawBuild();
      final day = List.generate(60, (i) => DateTime(2026, 1, 1).add(Duration(days: i)))
          .firstWhere((d) => !_sorts(salt, d, kWellInformedDailySamplingPercent));
      now = day;
      expect(await c.shouldShow(), isFalse);
    });

    test('stable dans la journée (pas de flicker entre rebuilds)', () async {
      final c = drawBuild();
      now = DateTime(2026, 4, 24, 8, 0);
      final a = await c.shouldShow();
      now = DateTime(2026, 4, 24, 22, 0); // même jour calendaire
      final b = await c.shouldShow();
      expect(a, equals(b));
    });

    test('échantillonne ~15% des jours éligibles', () async {
      final c = drawBuild();
      var count = 0;
      for (var i = 0; i < 700; i++) {
        now = DateTime(2026, 1, 1).add(Duration(days: i));
        if (await c.shouldShow()) count++;
      }
      expect(count / 700, closeTo(0.15, 0.06));
    });

    test('un salt différent décale les jours qui sortent', () {
      // Désync inter-installs : sur une fenêtre, deux salts n'allument pas les
      // mêmes jours.
      final days = List.generate(90, (i) => DateTime(2026, 1, 1).add(Duration(days: i)));
      final setA = days
          .where((d) => _sorts('salt-A', d, kWellInformedDailySamplingPercent))
          .map(_dayKey)
          .toSet();
      final setB = days
          .where((d) => _sorts('salt-B', d, kWellInformedDailySamplingPercent))
          .map(_dayKey)
          .toSet();
      expect(setA, isNot(equals(setB)));
    });
  });
}
