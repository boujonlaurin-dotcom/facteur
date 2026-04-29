import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeRepository repo;
  late DateTime now;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = _FakeRepository();
    now = DateTime(2026, 4, 24, 10, 0, 0);
  });

  WellInformedPromptController build() {
    final prefs = SharedPreferences.getInstance;
    return WellInformedPromptController(
      nudgeService: NudgeService(
        storage: NudgeStorage(),
        clock: () => now,
      ),
      repository: repo,
      clock: () => now,
      prefs: prefs,
    );
  }

  test('shouldShow true on fresh install', () async {
    final c = build();
    expect(await c.shouldShow(), isTrue);
  });

  test('after submit, blocked for 14 days', () async {
    final c = build();
    await c.submit(7);

    now = now.add(const Duration(days: 13, hours: 23));
    expect(await c.shouldShow(), isFalse);

    now = now.add(const Duration(hours: 2));
    // 14j + 1h écoulés depuis submit → shouldShow true à nouveau.
    expect(await c.shouldShow(), isTrue);
  });

  test('after skip, blocked for 5 days only', () async {
    final c = build();
    await c.skip();

    now = now.add(const Duration(days: 4, hours: 23));
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

  test('submit uses the long (14j) cooldown even after a prior skip', () async {
    final c = build();

    await c.skip();
    now = now.add(const Duration(days: 6));
    expect(await c.shouldShow(), isTrue);

    await c.submit(5);
    now = now.add(const Duration(days: 6));
    // Après submit, le cooldown long 14j domine le cooldown court du nudge.
    expect(await c.shouldShow(), isFalse);
  });

  test('uses nudge id well_informed_poll', () {
    expect(NudgeIds.wellInformedPoll, 'well_informed_poll');
  });
}
