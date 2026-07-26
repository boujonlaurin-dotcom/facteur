import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:facteur/features/feed/services/completed_reads_store.dart';

/// Epic 30 — durabilité de la lecture aboutie.
///
/// Avant ce registre, la complétion ne vivait qu'en mémoire : le filet vert
/// disparaissait au premier redémarrage de l'app, alors qu'une lecture aboutie
/// est définitive.
void main() {
  late Directory dir;
  late Box<String> box;
  late CompletedReadsStore store;

  setUp(() async {
    // Répertoire temporaire et non chemin en dur : deux fichiers de test qui
    // partagent un chemin Hive se marchent dessus en exécution parallèle.
    dir = Directory.systemTemp.createTempSync('completed_reads_test');
    Hive.init(dir.path);
    box = await Hive.openBox<String>(CompletedReadsStore.boxName);
    store = CompletedReadsStore(box);
  });

  tearDown(() async {
    await box.deleteFromDisk();
    await Hive.close();
    dir.deleteSync(recursive: true);
  });

  test('une complétion écrite est relue (cold start)', () async {
    await store.add('u1', 'c1');

    // Nouvelle instance sur la même box : ce que fait le boot de l'app.
    expect(CompletedReadsStore(box).idsForUser('u1'), {'c1'});
  });

  test('les utilisateurs sont isolés', () async {
    await store.add('u1', 'c1');
    await store.add('u2', 'c2');

    expect(store.idsForUser('u1'), {'c1'});
    expect(store.idsForUser('u2'), {'c2'});
  });

  test('clearForUser ne touche que son utilisateur', () async {
    await store.add('u1', 'c1');
    await store.add('u2', 'c2');

    await store.clearForUser('u1');

    expect(store.idsForUser('u1'), isEmpty);
    expect(store.idsForUser('u2'), {'c2'});
  });

  test('les entrées de plus de 30 jours sont purgées à l\'écriture', () async {
    final old = DateTime.now().subtract(const Duration(days: 31));
    await box.put('u1:vieux', old.toIso8601String());
    await box.put(
      'u1:recent',
      DateTime.now().subtract(const Duration(days: 29)).toIso8601String(),
    );

    await store.add('u1', 'neuf');

    expect(store.idsForUser('u1'), {'recent', 'neuf'});
  });

  test('une valeur illisible est traitée comme expirée', () async {
    await box.put('u1:corrompu', 'pas-une-date');

    await store.add('u1', 'c1');

    expect(store.idsForUser('u1'), {'c1'});
  });

  test('le cap en volume garde les entrées les plus récentes', () async {
    final base = DateTime.now().subtract(const Duration(days: 10));
    for (var i = 0; i < CompletedReadsStore.maxEntries + 5; i++) {
      await box.put(
        'u1:c$i',
        base.add(Duration(seconds: i)).toIso8601String(),
      );
    }

    // Déclenche la purge : maxEntries + 5 existantes + celle-ci.
    await store.add('u1', 'dernier');

    final ids = store.idsForUser('u1');
    expect(ids.length, CompletedReadsStore.maxEntries);
    expect(ids, contains('dernier'));
    // Les plus anciennes sont tombées en premier.
    expect(ids, isNot(contains('c0')));
    expect(ids, contains('c${CompletedReadsStore.maxEntries + 4}'));
  });

  test('box absente → tryFromHive rend null, jamais une exception', () async {
    await box.close();

    expect(CompletedReadsStore.tryFromHive(), isNull);

    // Réouverte pour le tearDown.
    box = await Hive.openBox<String>(CompletedReadsStore.boxName);
  });
}
