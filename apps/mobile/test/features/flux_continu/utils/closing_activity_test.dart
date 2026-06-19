import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';
import 'package:facteur/features/flux_continu/utils/closing_activity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickClosingActivities', () {
    final fixedDay = DateTime(2026, 6, 19); // jour de l'année déterministe

    test('renvoie 3 propositions distinctes par défaut', () {
      final picks = pickClosingActivities(
        condition: WeatherCondition.rainy,
        now: fixedDay,
      );
      expect(picks, hasLength(kClosingActivityCount));
      expect(picks.toSet().length, kClosingActivityCount);
    });

    test('sunny / partlyCloudy → l\'extérieur devient éligible', () {
      for (final c in [
        WeatherCondition.sunny,
        WeatherCondition.partlyCloudy,
      ]) {
        // Sur un cycle complet, au moins une journée tombe sur une activité
        // extérieure quand la météo le permet.
        final sawOutdoor = List.generate(
          kIndoorActivities.length + kOutdoorActivities.length,
          (i) => pickClosingActivities(
            condition: c,
            now: DateTime(2026, 1, 1).add(Duration(days: i)),
          ),
        ).any((picks) => picks.any((a) => a.isOutdoor));
        expect(sawOutdoor, isTrue, reason: 'condition $c should allow outdoor');
      }
    });

    test('cloudy / rainy / snowy / null → uniquement l\'intérieur', () {
      for (final c in [
        null,
        WeatherCondition.cloudy,
        WeatherCondition.rainy,
        WeatherCondition.snowy,
      ]) {
        for (var i = 0; i < kIndoorActivities.length; i++) {
          final picks = pickClosingActivities(
            condition: c,
            now: DateTime(2026, 1, 1).add(Duration(days: i)),
          );
          expect(
            picks.every((a) => !a.isOutdoor),
            isTrue,
            reason: 'condition $c should stay indoor',
          );
        }
      }
    });

    test('déterministe pour un jour fixe', () {
      final a = pickClosingActivities(
        condition: WeatherCondition.sunny,
        now: fixedDay,
      );
      final b = pickClosingActivities(
        condition: WeatherCondition.sunny,
        now: fixedDay,
      );
      expect(a, equals(b));
    });

    test('la sélection tourne d\'un jour à l\'autre', () {
      final d0 = pickClosingActivities(
        condition: WeatherCondition.rainy,
        now: DateTime(2026, 1, 1),
      );
      final d1 = pickClosingActivities(
        condition: WeatherCondition.rainy,
        now: DateTime(2026, 1, 2),
      );
      expect(d0, isNot(equals(d1)));
    });

    test('reste dans les bornes pour n\'importe quel jour', () {
      for (var i = 0; i < 370; i++) {
        final day = DateTime(2026, 1, 1).add(Duration(days: i));
        expect(
          () => pickClosingActivities(condition: null, now: day),
          returnsNormally,
        );
      }
    });
  });
}
