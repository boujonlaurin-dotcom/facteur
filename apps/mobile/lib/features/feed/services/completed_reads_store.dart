import 'package:hive_flutter/hive_flutter.dart';

/// Registre durable des lectures **abouties** (Epic 30).
///
/// Box dédiée, séparée de `pending_reads` : cette dernière est une file de
/// synchro dont `flushForUser` **supprime** l'entrée au succès. File de synchro
/// et registre d'état ont des cycles de vie opposés — les mélanger ferait
/// disparaître la complétion au premier flush réussi.
///
/// Elle est aussi préférée à un patch des snapshots de cache : `feed_cache` a
/// un TTL de 10 min et `flux_continu_cache` s'invalide au changement de
/// `day_key`, alors qu'une lecture aboutie est définitive.
class CompletedReadsStore {
  static const boxName = 'completed_reads';

  /// Au-delà, une complétion n'éclaire plus aucune carte à l'écran : le feed
  /// ne remonte pas si loin. Le serveur reste la source de vérité longue durée.
  static const maxAge = Duration(days: 30);

  /// ~2 ans à 1,2 complétion/jour actif, pour ~50 Ko sur disque.
  static const maxEntries = 1000;

  final Box<String> box;

  CompletedReadsStore(this.box);

  /// `null` si la box n'a pas pu être ouverte au boot — l'appelant retombe
  /// alors sur l'état mémoire seul, jamais sur une exception.
  static CompletedReadsStore? tryFromHive() {
    if (!Hive.isBoxOpen(boxName)) return null;
    return CompletedReadsStore(Hive.box<String>(boxName));
  }

  String _key(String userId, String contentId) => '$userId:$contentId';

  Set<String> idsForUser(String userId) {
    final prefix = '$userId:';
    return {
      for (final key in box.keys.whereType<String>())
        if (key.startsWith(prefix)) key.substring(prefix.length),
    };
  }

  Future<void> add(String userId, String contentId) async {
    if (userId.isEmpty || contentId.isEmpty) return;
    await box.put(_key(userId, contentId), DateTime.now().toIso8601String());
    // Bornage à l'écriture et non au boot : le cold start est le chemin
    // critique de l'app, et la box n'a de raison de grandir qu'ici.
    await _prune();
  }

  Future<void> clearForUser(String userId) async {
    final prefix = '$userId:';
    await box.deleteAll(
      box.keys.whereType<String>().where((key) => key.startsWith(prefix)),
    );
  }

  Future<void> _prune() async {
    final now = DateTime.now();
    final expired = <String>[];
    final dated = <MapEntry<String, DateTime>>[];

    for (final key in box.keys.whereType<String>()) {
      final stamp = DateTime.tryParse(box.get(key) ?? '');
      // Valeur illisible : on la traite comme expirée plutôt que de la garder
      // indéfiniment hors de portée du cap par âge.
      if (stamp == null || now.difference(stamp) > maxAge) {
        expired.add(key);
        continue;
      }
      dated.add(MapEntry(key, stamp));
    }

    if (expired.isNotEmpty) await box.deleteAll(expired);
    if (dated.length <= maxEntries) return;

    dated.sort((a, b) => a.value.compareTo(b.value));
    await box.deleteAll(
      dated.take(dated.length - maxEntries).map((e) => e.key),
    );
  }
}
