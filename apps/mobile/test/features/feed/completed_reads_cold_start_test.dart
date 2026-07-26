import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:facteur/features/feed/services/completed_reads_store.dart';
import 'package:facteur/features/feed/services/read_sync_service.dart';
import 'package:facteur/features/gamification/models/streak_model.dart';
import 'package:facteur/features/gamification/providers/streak_provider.dart';

/// Epic 30 — la complétion doit survivre au redémarrage de l'app.
///
/// Avant, `markCompleted` ne touchait aucun stockage durable : la lecture
/// aboutie ne vivait que dans `completedContentIdsProvider`, en mémoire.
void main() {
  late Directory tempDir;
  late Box<String> readsBox;
  late Box<String> completedBox;

  setUpAll(() async {
    tempDir = await Directory.systemTemp.createTemp('completed_cold_start_');
    Hive.init(tempDir.path);
    readsBox = await Hive.openBox<String>(PendingReadQueue.boxName);
    completedBox = await Hive.openBox<String>(CompletedReadsStore.boxName);
  });

  setUp(() async {
    await readsBox.clear();
    await completedBox.clear();
  });

  tearDownAll(() async {
    await Hive.close();
    await tempDir.delete(recursive: true);
  });

  /// Laisse le flush asynchrone (`unawaited` dans `markCompleted`) se terminer
  /// avant la fin du test, sinon il lit un conteneur déjà disposé.
  ///
  /// Des tours de boucle *réels* (1 ms) et non `Duration.zero` : le flush
  /// traverse des E/S Hive, et 4 microtâches suffisaient à vide mais pas sous
  /// la charge de la suite complète — le conteneur était disposé en plein vol.
  Future<void> settle() async {
    for (var i = 0; i < 20; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 1));
    }
  }

  ProviderContainer container({required String userId}) {
    final c = ProviderContainer(
      overrides: [
        // Court-circuite `Supabase.instance` (non initialisé en test unitaire).
        readSyncUserIdProvider.overrideWithValue(userId),
        // Le flush relit le compteur du jour côté serveur : hors périmètre.
        streakProvider.overrideWith(_FakeStreakNotifier.new),
        readSyncServiceProvider.overrideWith(
          (ref) => ReadSyncService(
            ref,
            // Pas de réseau : on teste la durabilité, pas la synchro.
            completionSyncOverride: (_, __) async {},
          ),
        ),
      ],
    );
    addTearDown(c.dispose);
    return c;
  }

  test('une complétion survit à un nouveau ProviderContainer', () async {
    final first = container(userId: 'u1');
    await first
        .read(readSyncServiceProvider)
        .markCompleted('c1', CompletionSource.web);

    await settle();
    expect(first.read(completedContentIdsProvider), contains('c1'));

    // Redémarrage de l'app : nouveau conteneur, mêmes boxes Hive.
    final second = container(userId: 'u1');
    expect(second.read(completedContentIdsProvider), isEmpty);

    second.read(readSyncServiceProvider).hydrateCompletedReads();

    expect(second.read(completedContentIdsProvider), contains('c1'));
  });

  test('l\'hydratation est scopée à l\'utilisateur', () async {
    await container(userId: 'u1')
        .read(readSyncServiceProvider)
        .markCompleted('c1', CompletionSource.inApp);

    await settle();

    final other = container(userId: 'u2');
    other.read(readSyncServiceProvider).hydrateCompletedReads();

    expect(other.read(completedContentIdsProvider), isEmpty);
  });

  test('markCompleted est idempotent', () async {
    final c = container(userId: 'u1');
    final service = c.read(readSyncServiceProvider);

    expect(await service.markCompleted('c1', CompletionSource.inApp), isTrue);
    expect(await service.markCompleted('c1', CompletionSource.inApp), isFalse);
    await settle();
  });

  test('les erreurs de connectivité ne sont pas remontées', () {
    // Hors-ligne est le cas nominal de cette file : la noyer sous ce bruit
    // rendrait le signal inutile.
    expect(
      isOfflineError(
        DioException.connectionError(
          requestOptions: RequestOptions(),
          reason: 'offline',
        ),
      ),
      isTrue,
    );
    expect(isOfflineError(StateError('contrat cassé')), isFalse);
  });
}

class _FakeStreakNotifier extends StreakNotifier {
  @override
  Future<StreakModel> build() async => const StreakModel(
        currentStreak: 0,
        longestStreak: 0,
        weeklyCount: 0,
        weeklyGoal: 10,
        weeklyProgress: 0.0,
      );

  @override
  Future<void> refreshSilent() async {}
}
