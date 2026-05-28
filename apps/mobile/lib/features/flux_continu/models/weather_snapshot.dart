/// 5-bucket Facteur weather taxonomy. Mapped from Open-Meteo's WMO codes
/// (https://open-meteo.com/en/docs#weathervariables) by [weatherConditionFromWmo].
enum WeatherCondition { sunny, partlyCloudy, cloudy, rainy, snowy }

extension WeatherConditionAsset on WeatherCondition {
  String get assetName {
    switch (this) {
      case WeatherCondition.sunny:
        return 'sunny';
      case WeatherCondition.partlyCloudy:
        return 'partly_cloudy';
      case WeatherCondition.cloudy:
        return 'cloudy';
      case WeatherCondition.rainy:
        return 'rainy';
      case WeatherCondition.snowy:
        return 'snowy';
    }
  }
}

/// Maps an Open-Meteo WMO `weather_code` to one of the 5 Facteur buckets.
/// Unknown codes default to [WeatherCondition.cloudy] (visually neutral).
WeatherCondition weatherConditionFromWmo(int code) {
  if (code == 0) return WeatherCondition.sunny;
  if (code == 1 || code == 2) return WeatherCondition.partlyCloudy;
  if (code == 3 || code == 45 || code == 48) return WeatherCondition.cloudy;
  if ((code >= 51 && code <= 67) ||
      (code >= 80 && code <= 82) ||
      (code >= 95 && code <= 99)) {
    return WeatherCondition.rainy;
  }
  if ((code >= 71 && code <= 77) || code == 85 || code == 86) {
    return WeatherCondition.snowy;
  }
  return WeatherCondition.cloudy;
}

class WeatherSnapshot {
  final WeatherCondition condition;
  final int currentC;
  final int minC;
  final int maxC;
  final DateTime fetchedAt;

  const WeatherSnapshot({
    required this.condition,
    required this.currentC,
    required this.minC,
    required this.maxC,
    required this.fetchedAt,
  });
}
