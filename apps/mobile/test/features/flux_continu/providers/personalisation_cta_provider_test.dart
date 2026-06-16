import 'package:facteur/core/nudges/nudge_coordinator.dart';
import 'package:facteur/core/nudges/nudge_ids.dart';
import 'package:facteur/core/nudges/nudge_service.dart';
import 'package:facteur/core/nudges/nudge_storage.dart';
import 'package:facteur/features/flux_continu/providers/personalisation_cta_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late DateTime now;
  late SharedPreferences prefs;
  late ProviderContainer container;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    prefs = await SharedPreferences.getInstance();
    now = DateTime.utc(2026, 6, 11, 12);
    container = ProviderContainer(
      overrides: [
        nudgeServiceProvider.overrideWithValue(
          NudgeService(
            storage: NudgeStorage(prefs: prefs),
            clock: () => now,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  Future<bool> eligibility() {
    return container.read(personalisationCtaShouldShowProvider.future);
  }

  test('est éligible sans activation précédente', () async {
    expect(await eligibility(), isTrue);
  });

  test('activation retire immédiatement et persiste le timestamp', () async {
    await eligibility();

    final activation = container
        .read(personalisationCtaShouldShowProvider.notifier)
        .activate();

    expect(
      container.read(personalisationCtaShouldShowProvider).valueOrNull,
      isFalse,
    );
    await activation;
    expect(
      prefs.getInt('nudge.${NudgeIds.personalisationCta}.lastShown'),
      now.millisecondsSinceEpoch,
    );
  });

  test('reste masquée avant 30 jours', () async {
    await prefs.setInt(
      'nudge.${NudgeIds.personalisationCta}.lastShown',
      now.subtract(const Duration(days: 29)).millisecondsSinceEpoch,
    );

    container.invalidate(personalisationCtaShouldShowProvider);

    expect(await eligibility(), isFalse);
  });

  test('redevient éligible à partir de 30 jours', () async {
    await prefs.setInt(
      'nudge.${NudgeIds.personalisationCta}.lastShown',
      now.subtract(const Duration(days: 30)).millisecondsSinceEpoch,
    );

    container.invalidate(personalisationCtaShouldShowProvider);

    expect(await eligibility(), isTrue);
  });
}
