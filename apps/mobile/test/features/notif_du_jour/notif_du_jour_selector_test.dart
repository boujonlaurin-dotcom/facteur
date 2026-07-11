import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/notif_du_jour/providers/notif_du_jour_provider.dart';

void main() {
  const candidates = [
    NotifCandidate('serein', 0.4),
    NotifCandidate('tournee', 0.5),
    NotifCandidate('veille', 0.6),
    NotifCandidate('recommencer', 0.1),
  ];

  group('notifJitter', () {
    test('déterministe pour un couple (jour, id)', () {
      expect(notifJitter('serein', 100), notifJitter('serein', 100));
      expect(notifIdHash('serein'), notifIdHash('serein'));
    });

    test('borné à [0, kRotationJitter]', () {
      for (var d = 0; d < 400; d++) {
        for (final id in ['serein', 'tournee', 'veille', 'source']) {
          final j = notifJitter(id, d);
          expect(j, greaterThanOrEqualTo(0));
          expect(j, lessThan(kRotationJitter));
        }
      }
    });

    test('varie selon le jour', () {
      final values = {for (var d = 0; d < 30; d++) notifJitter('serein', d)};
      expect(values.length, greaterThan(1));
    });
  });

  group('rankNotifQueue', () {
    test('ordre stable intra-jour', () {
      final a = rankNotifQueue(candidates, 20000);
      final b = rankNotifQueue(candidates, 20000);
      expect(a, b);
    });

    test('tourne inter-jour pour des pertinences proches', () {
      // serein (0.4) / tournee (0.5) / veille (0.6) sont dans la fenêtre du
      // jitter (0.15) : sur 60 jours, l'ordre doit permuter au moins une fois.
      final orders = <String>{};
      for (var d = 0; d < 60; d++) {
        orders.add(rankNotifQueue(candidates, d).join(','));
      }
      expect(orders.length, greaterThan(1));
    });

    test('une pertinence forte reste en tête malgré le jitter', () {
      // 1.0 (0 source) ne peut pas passer sous un 0.6 avec ε = 0.15.
      final withStrong = [
        ...candidates,
        const NotifCandidate('source', 1.0),
      ];
      for (var d = 0; d < 365; d++) {
        expect(rankNotifQueue(withStrong, d).first, 'source');
      }
    });

    test('le fallback (0.1) reste derrière tout le monde', () {
      for (var d = 0; d < 365; d++) {
        expect(rankNotifQueue(candidates, d).last, 'recommencer');
      }
    });

    test('couverture de rotation : les écarts < ε permutent, pas les autres',
        () {
      // veille (0.6) / tournee (0.5) : écart 0.1 < ε 0.15 → chacun passe
      // premier certains jours. serein (0.4) est à 0.2 de veille (> ε) :
      // il ne prend jamais la tête — la rotation ne zappe pas le pertinent.
      final firsts = <String>{};
      var sereinBeatsTournee = false;
      for (var d = 0; d < 365; d++) {
        final order = rankNotifQueue(candidates, d);
        firsts.add(order.first);
        sereinBeatsTournee |=
            order.indexOf('serein') < order.indexOf('tournee');
      }
      expect(firsts, containsAll(['tournee', 'veille']));
      expect(firsts, isNot(contains('serein')));
      expect(sereinBeatsTournee, isTrue);
    });

    test('liste vide → file vide (le fallback vit dans le provider)', () {
      expect(rankNotifQueue(const [], 10), isEmpty);
    });
  });

  test('notifEpochDay constant sur la journée UTC', () {
    expect(
      notifEpochDay(DateTime.utc(2026, 7, 3, 0, 1)),
      notifEpochDay(DateTime.utc(2026, 7, 3, 23, 59)),
    );
    expect(
      notifEpochDay(DateTime.utc(2026, 7, 4)),
      notifEpochDay(DateTime.utc(2026, 7, 3)) + 1,
    );
  });
}
