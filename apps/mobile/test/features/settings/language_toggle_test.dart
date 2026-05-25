import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:facteur/features/custom_topics/providers/personalization_provider.dart';
import 'package:facteur/features/feed/repositories/personalization_repository.dart';
import 'package:facteur/features/settings/providers/language_preference_provider.dart';

/// Fake repository — capture les appels et permet d'injecter une erreur.
class _FakePersonalizationRepo implements PersonalizationRepository {
  bool throwOnToggle = false;
  bool? lastValue;
  int callCount = 0;

  @override
  Future<void> toggleHideNonFrSources(bool hideNonFr) async {
    callCount++;
    lastValue = hideNonFr;
    if (throwOnToggle) throw Exception('boom');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

ProviderContainer _container({
  required _FakePersonalizationRepo repo,
  required UserPersonalization remote,
}) {
  return ProviderContainer(
    overrides: [
      personalizationRepositoryProvider.overrideWithValue(repo),
      personalizationProvider.overrideWith((ref) async => remote),
    ],
  );
}

Future<void> _waitForSync(ProviderContainer container) async {
  // Boot async : load Hive → sync backend → synced = true
  while (!container.read(languagePreferenceProvider).synced) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
    await Hive.openBox<dynamic>('settings');
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  test('toggle(true) persist Hive + POST repo + userSet=true', () async {
    final repo = _FakePersonalizationRepo();
    final container = _container(
      repo: repo,
      remote: const UserPersonalization(
        hideNonFrSources: false,
        languageFilterUserSet: false,
      ),
    );
    addTearDown(container.dispose);

    await _waitForSync(container);
    expect(container.read(languagePreferenceProvider).hideNonFr, false);

    final ok = await container
        .read(languagePreferenceProvider.notifier)
        .toggle(true);

    expect(ok, true);
    expect(repo.lastValue, true);
    expect(repo.callCount, 1);
    final state = container.read(languagePreferenceProvider);
    expect(state.hideNonFr, true);
    expect(state.userSet, true);

    final box = Hive.box<dynamic>('settings');
    expect(box.get('hide_non_fr_sources'), true);
    expect(box.get('language_filter_user_set'), true);
  });

  test('toggle rollback on HTTP error → state revient + retour false',
      () async {
    final repo = _FakePersonalizationRepo()..throwOnToggle = true;
    final container = _container(
      repo: repo,
      remote: const UserPersonalization(
        hideNonFrSources: false,
        languageFilterUserSet: false,
      ),
    );
    addTearDown(container.dispose);

    await _waitForSync(container);
    final before = container.read(languagePreferenceProvider);
    expect(before.hideNonFr, false);

    final ok = await container
        .read(languagePreferenceProvider.notifier)
        .toggle(true);

    expect(ok, false);
    final after = container.read(languagePreferenceProvider);
    expect(after.hideNonFr, false);
    expect(after.userSet, false);
  });

  test('refresh() resync state depuis /personalization', () async {
    final repo = _FakePersonalizationRepo();
    final container = _container(
      repo: repo,
      remote: const UserPersonalization(
        hideNonFrSources: true,
        languageFilterUserSet: false,
      ),
    );
    addTearDown(container.dispose);

    await _waitForSync(container);
    expect(container.read(languagePreferenceProvider).hideNonFr, true);

    // Le backend a recalculé : maintenant hideNonFr=false.
    container.updateOverrides([
      personalizationRepositoryProvider.overrideWithValue(repo),
      personalizationProvider.overrideWith(
        (ref) async => const UserPersonalization(
          hideNonFrSources: false,
          languageFilterUserSet: false,
        ),
      ),
    ]);

    await container
        .read(languagePreferenceProvider.notifier)
        .refresh();

    final state = container.read(languagePreferenceProvider);
    expect(state.hideNonFr, false);
    expect(state.userSet, false);

    final box = Hive.box<dynamic>('settings');
    expect(box.get('hide_non_fr_sources'), false);
  });
}
