import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';
import 'package:facteur/features/flux_continu/repositories/weather_repository.dart';

void main() {
  group('WeatherRepository.parseForecast', () {
    // Corps Open-Meteo réaliste : current + daily sur 5 jours.
    final body = <String, dynamic>{
      'current': {
        'temperature_2m': 18.6,
        'apparent_temperature': 17.1,
        'weather_code': 3, // overcast → cloudy
      },
      'daily': {
        'time': [
          '2026-06-01',
          '2026-06-02',
          '2026-06-03',
          '2026-06-04',
          '2026-06-05',
        ],
        'weather_code': [0, 1, 61, 71, 45],
        'temperature_2m_max': [21.4, 23.0, 19.8, 5.2, 16.0],
        'temperature_2m_min': [11.9, 12.3, 13.0, -1.4, 9.0],
      },
    };

    test('maps current conditions, feels-like and 5-day forecast', () {
      final f = WeatherRepository.parseForecast(body);

      expect(f.condition, WeatherCondition.cloudy); // from current code 3
      expect(f.currentC, 19); // 18.6 rounded
      expect(f.feelsLikeC, 17); // 17.1 rounded
      expect(f.days.length, 5);

      // Top-level min/max come from today (days[0]).
      expect(f.minC, 12); // 11.9 rounded
      expect(f.maxC, 21); // 21.4 rounded
    });

    test('parses per-day condition mapping and rounding', () {
      final f = WeatherRepository.parseForecast(body);

      expect(f.days[0].condition, WeatherCondition.sunny); // code 0
      expect(f.days[1].condition, WeatherCondition.partlyCloudy); // code 1
      expect(f.days[2].condition, WeatherCondition.rainy); // code 61
      expect(f.days[3].condition, WeatherCondition.snowy); // code 71
      expect(f.days[4].condition, WeatherCondition.cloudy); // code 45

      expect(f.days[0].date, DateTime(2026, 6, 1));
      expect(f.days[3].minC, -1); // -1.4 rounded
      expect(f.days[3].maxC, 5); // 5.2 rounded
    });
  });
}
