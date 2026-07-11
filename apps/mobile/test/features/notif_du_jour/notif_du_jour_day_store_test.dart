import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_day_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> settle() => Future<void>.delayed(Duration.zero);

  test('chargement : jour vierge si rien de persisté', () async {
    SharedPreferences.setMockInitialValues({});
    final store = NotifDuJourDayStore();
    await settle();
    expect(store.state.loaded, isTrue);
    expect(store.state.consumed, isEmpty);
  });

  test('chargement : reprend les consommés du même jour', () async {
    final today = notifDuJourDayKey(DateTime.now());
    SharedPreferences.setMockInitialValues({
      kNotifDuJourStateKey: jsonEncode({
        'day': today,
        'consumed': ['serein', 'veille'],
      }),
    });
    final store = NotifDuJourDayStore();
    await settle();
    expect(store.state.consumed, ['serein', 'veille']);
  });

  test('chargement : reset au changement de jour', () async {
    SharedPreferences.setMockInitialValues({
      kNotifDuJourStateKey: jsonEncode({
        'day': '2020-01-01',
        'consumed': ['serein', 'veille', 'tournee'],
      }),
    });
    final store = NotifDuJourDayStore();
    await settle();
    expect(store.state.consumed, isEmpty);
    expect(store.state.capReached, isFalse);
  });

  test('consume persiste id + jour, idempotent', () async {
    SharedPreferences.setMockInitialValues({});
    final store = NotifDuJourDayStore();
    await settle();
    await store.consume('serein');
    await store.consume('serein');
    await store.consume('veille');
    expect(store.state.consumed, ['serein', 'veille']);

    final prefs = await SharedPreferences.getInstance();
    final raw = jsonDecode(prefs.getString(kNotifDuJourStateKey)!)
        as Map<String, dynamic>;
    expect(raw['day'], notifDuJourDayKey(DateTime.now()));
    expect(raw['consumed'], ['serein', 'veille']);
  });

  test('cap atteint à 3 consommés', () async {
    SharedPreferences.setMockInitialValues({});
    final store = NotifDuJourDayStore();
    await settle();
    await store.consume('a');
    await store.consume('b');
    expect(store.state.capReached, isFalse);
    await store.consume('c');
    expect(store.state.capReached, isTrue);
  });

  test('minuit franchi entre chargement et consume → reset', () async {
    SharedPreferences.setMockInitialValues({});
    var now = DateTime(2026, 7, 3, 23, 50);
    final store = NotifDuJourDayStore(clock: () => now);
    await settle();
    await store.consume('serein');
    expect(store.state.consumed, ['serein']);

    now = DateTime(2026, 7, 4, 0, 10);
    await store.consume('veille');
    expect(store.state.day, '2026-07-04');
    expect(store.state.consumed, ['veille']);
  });
}
