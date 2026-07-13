import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_dismissal_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('chargement : vide si rien de persisté', () async {
    SharedPreferences.setMockInitialValues({});
    final store = NotifDuJourDismissalStore();
    await settle();
    expect(store.state.loaded, isTrue);
    expect(store.state.dismissedOn, isEmpty);
  });

  test('chargement : reprend les dismiss persistés', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey: jsonEncode({
        'serein': '2026-07-01',
        'veille': '2026-06-15',
      }),
    });
    final store = NotifDuJourDismissalStore();
    await settle();
    expect(store.state.dismissedOn, {
      'serein': '2026-07-01',
      'veille': '2026-06-15',
    });
  });

  test('recordDismissed pose la date du jour et persiste', () async {
    SharedPreferences.setMockInitialValues({});
    final now = DateTime(2026, 7, 10, 8, 30);
    final store = NotifDuJourDismissalStore(clock: () => now);
    await settle();

    await store.recordDismissed('serein');
    expect(store.state.dismissedOn['serein'], '2026-07-10');

    final prefs = await SharedPreferences.getInstance();
    final raw = jsonDecode(prefs.getString(kNotifDuJourDismissalsKey)!)
        as Map<String, dynamic>;
    expect(raw['serein'], '2026-07-10');
  });

  test('recordDismissed écrase la date précédente du même id', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey: jsonEncode({'serein': '2026-06-01'}),
    });
    var now = DateTime(2026, 7, 10);
    final store = NotifDuJourDismissalStore(clock: () => now);
    await settle();

    await store.recordDismissed('serein');
    expect(store.state.dismissedOn['serein'], '2026-07-10');
  });

  test('activeCooldownIds : id dismissé < 30j est actif', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey: jsonEncode({'serein': '2026-07-01'}),
    });
    final store = NotifDuJourDismissalStore();
    await settle();

    // 9 jours après le dismiss → toujours en cooldown.
    expect(
      store.state.activeCooldownIds(DateTime(2026, 7, 10)),
      contains('serein'),
    );
  });

  test('activeCooldownIds : cooldown expiré après 30j', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey: jsonEncode({'serein': '2026-06-01'}),
    });
    final store = NotifDuJourDismissalStore();
    await settle();

    // 30 jours pile après → hors cooldown (< 30 strict).
    expect(
      store.state.activeCooldownIds(DateTime(2026, 7, 1)),
      isNot(contains('serein')),
    );
    // 40 jours après → hors cooldown.
    expect(
      store.state.activeCooldownIds(DateTime(2026, 7, 11)),
      isEmpty,
    );
  });

  test('activeCooldownIds : date illisible ignorée', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourDismissalsKey: jsonEncode({'serein': 'pas-une-date'}),
    });
    final store = NotifDuJourDismissalStore();
    await settle();
    expect(store.state.activeCooldownIds(DateTime(2026, 7, 10)), isEmpty);
  });
}
