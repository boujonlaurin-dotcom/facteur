import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/flux_continu/models/weather_snapshot.dart';

void main() {
  group('weatherConditionFromWmo', () {
    test('maps clear sky to sunny', () {
      expect(weatherConditionFromWmo(0), WeatherCondition.sunny);
    });

    test('maps mainly clear / partly cloudy to partlyCloudy', () {
      expect(weatherConditionFromWmo(1), WeatherCondition.partlyCloudy);
      expect(weatherConditionFromWmo(2), WeatherCondition.partlyCloudy);
    });

    test('maps overcast and fog to cloudy', () {
      expect(weatherConditionFromWmo(3), WeatherCondition.cloudy);
      expect(weatherConditionFromWmo(45), WeatherCondition.cloudy);
      expect(weatherConditionFromWmo(48), WeatherCondition.cloudy);
    });

    test('maps drizzle / rain / showers / thunder to rainy', () {
      expect(weatherConditionFromWmo(51), WeatherCondition.rainy);
      expect(weatherConditionFromWmo(63), WeatherCondition.rainy);
      expect(weatherConditionFromWmo(80), WeatherCondition.rainy);
      expect(weatherConditionFromWmo(95), WeatherCondition.rainy);
    });

    test('maps snow / snow showers to snowy', () {
      expect(weatherConditionFromWmo(71), WeatherCondition.snowy);
      expect(weatherConditionFromWmo(75), WeatherCondition.snowy);
      expect(weatherConditionFromWmo(85), WeatherCondition.snowy);
      expect(weatherConditionFromWmo(86), WeatherCondition.snowy);
    });

    test('falls back to cloudy on unknown codes', () {
      expect(weatherConditionFromWmo(999), WeatherCondition.cloudy);
    });
  });

  test('WeatherCondition.assetName matches the SVG slugs shipped in assets',
      () {
    expect(WeatherCondition.sunny.assetName, 'sunny');
    expect(WeatherCondition.partlyCloudy.assetName, 'partly_cloudy');
    expect(WeatherCondition.cloudy.assetName, 'cloudy');
    expect(WeatherCondition.rainy.assetName, 'rainy');
    expect(WeatherCondition.snowy.assetName, 'snowy');
  });
}
