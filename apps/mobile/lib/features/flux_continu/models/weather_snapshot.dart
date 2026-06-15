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

/// Une journée de prévision (today = `days[0]` dans [WeatherForecast]).
class WeatherDay {
  final DateTime date;
  final WeatherCondition condition;
  final int minC;
  final int maxC;

  const WeatherDay({
    required this.date,
    required this.condition,
    required this.minC,
    required this.maxC,
  });
}

/// Prévision météo riche alimentant à la fois le badge du header (champs
/// `condition` / `currentC` / `minC` / `maxC`) et la modal détaillée
/// (`feelsLikeC` + [days] sur 5 jours). Un seul fetch sert les deux usages.
class WeatherForecast {
  final WeatherCondition condition;
  final int currentC;
  final int feelsLikeC;
  final int minC;
  final int maxC;
  final DateTime fetchedAt;

  /// Prévision sur 5 jours, today inclus en `days[0]`.
  final List<WeatherDay> days;

  const WeatherForecast({
    required this.condition,
    required this.currentC,
    required this.feelsLikeC,
    required this.minC,
    required this.maxC,
    required this.fetchedAt,
    required this.days,
  });
}
