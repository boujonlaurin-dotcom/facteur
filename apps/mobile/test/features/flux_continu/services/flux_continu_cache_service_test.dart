import 'dart:io';

import 'package:facteur/features/digest/models/dual_digest_response.dart';
import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:facteur/features/flux_continu/services/flux_continu_cache_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

/// Tests de [FluxContinuCacheService.readLatest] — la primitive du démarrage
/// matinal quasi-instantané. `readLatest` ne jette plus sur un day mismatch
/// (cache d'hier invalidé chaque nuit) : il pose `isStale` pour que le provider
/// dessine un squelette fidèle sans jamais afficher de contenu périmé.
/// `readToday` reste le wrapper « du jour uniquement ».
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  DualDigestResponse dual() => DualDigestResponse(sereinEnabled: false);

  Future<Box<String>> box() async {
    return Hive.isBoxOpen(FluxContinuCacheService.boxName)
        ? Hive.box<String>(FluxContinuCacheService.boxName)
        : await Hive.openBox<String>(FluxContinuCacheService.boxName);
  }

  setUpAll(() {
    tempDir = Directory.systemTemp.createTempSync('flux_cache_test');
    Hive.init(tempDir.path);
  });

  setUp(() async {
    await (await box()).clear();
  });

  tearDownAll(() async {
    await Hive.close();
    tempDir.deleteSync(recursive: true);
  });

  test('empty cache → readLatest & readToday both null', () async {
    final service = FluxContinuCacheService();
    expect(await service.readLatest(), isNull);
    expect(await service.readToday(), isNull);
  });

  test('snapshot du jour → isStale:false, savedAt non-null, readToday le sert',
      () async {
    final service = FluxContinuCacheService();
    final now = DateTime(2026, 6, 9, 12);
    await service.write(
      dual: dual(),
      topThemes: const [TopTheme(interestSlug: 'tech', weight: 1)],
      essentielArticles: const [],
      now: now,
    );

    final latest = await service.readLatest(now: now);
    expect(latest, isNotNull);
    expect(latest!.isStale, isFalse);
    expect(latest.savedAt, isNotNull);
    expect(latest.topThemes.map((t) => t.interestSlug), ['tech']);

    // Le wrapper « du jour » sert bien le snapshot non périmé.
    final today = await service.readToday(now: now);
    expect(today, isNotNull);
    expect(today!.isStale, isFalse);
  });

  test('snapshot d\'hier → readLatest isStale:true, readToday null', () async {
    final service = FluxContinuCacheService();
    // Écrit avec un jour passé (bien au-delà de la frontière 07h30).
    await service.write(
      dual: dual(),
      topThemes: const [],
      essentielArticles: const [],
      now: DateTime(2020, 1, 1, 12),
    );

    // Lu « aujourd'hui » → day mismatch.
    final latest = await service.readLatest(now: DateTime(2026, 6, 9, 12));
    expect(latest, isNotNull, reason: 'le snapshot reste lisible (squelette)');
    expect(latest!.isStale, isTrue);

    // readToday refuse tout snapshot périmé.
    expect(await service.readToday(now: DateTime(2026, 6, 9, 12)), isNull);
  });

  test('JSON corrompu → readLatest null (pas d\'exception)', () async {
    final b = await box();
    await b.put('latest_snapshot', '{ this is : not json');
    final service = FluxContinuCacheService();
    expect(await service.readLatest(), isNull);
    expect(await service.readToday(), isNull);
  });

  test('payload sans clé `dual` → readLatest null', () async {
    final b = await box();
    await b.put('latest_snapshot', '{"day_key":"2026-06-09"}');
    final service = FluxContinuCacheService();
    expect(await service.readLatest(now: DateTime(2026, 6, 9, 12)), isNull);
  });
}
