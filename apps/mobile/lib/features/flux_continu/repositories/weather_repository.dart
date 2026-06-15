import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather_snapshot.dart';

/// Coordonnées de repli (Paris) utilisées quand l'utilisateur n'a pas (encore)
/// partagé sa position. Mêmes valeurs que [WeatherLocation.paris].
const double kParisLat = 48.8566;
const double kParisLng = 2.3522;

class WeatherRepository {
  final Dio _dio;

  WeatherRepository(this._dio);

  /// Récupère la prévision Open-Meteo (sans clé API) pour des coordonnées
  /// arbitraires : conditions courantes + ressenti + 5 jours.
  ///
  /// [timezone] = `'auto'` laisse Open-Meteo aligner les bornes journalières
  /// sur le fuseau du point demandé (correct pour une position device).
  Future<WeatherForecast> fetch(
    double lat,
    double lng, {
    String timezone = 'auto',
  }) async {
    final response = await _dio.get<Map<String, dynamic>>(
      'https://api.open-meteo.com/v1/forecast',
      queryParameters: {
        'latitude': lat,
        'longitude': lng,
        'current': 'temperature_2m,apparent_temperature,weather_code',
        'daily': 'weather_code,temperature_2m_max,temperature_2m_min',
        'timezone': timezone,
        'forecast_days': 5,
      },
      options: Options(
        receiveTimeout: const Duration(seconds: 4),
        sendTimeout: const Duration(seconds: 4),
      ),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('Open-Meteo returned an empty body');
    }
    return parseForecast(data);
  }

  /// Parse exposé pour les tests : transforme le corps Open-Meteo en
  /// [WeatherForecast]. `current` porte les conditions instantanées,
  /// `daily` les bornes min/max et le code par jour (5 entrées).
  static WeatherForecast parseForecast(Map<String, dynamic> data) {
    final current = (data['current'] as Map).cast<String, dynamic>();
    final daily = (data['daily'] as Map).cast<String, dynamic>();

    final currentC = (current['temperature_2m'] as num).round();
    final feelsLikeC = (current['apparent_temperature'] as num).round();
    final currentCode = (current['weather_code'] as num).toInt();

    final dates = (daily['time'] as List).cast<String>();
    final codes = (daily['weather_code'] as List).cast<num>();
    final maxList = (daily['temperature_2m_max'] as List).cast<num>();
    final minList = (daily['temperature_2m_min'] as List).cast<num>();

    final days = <WeatherDay>[
      for (var i = 0; i < dates.length; i++)
        WeatherDay(
          date: DateTime.parse(dates[i]),
          condition: weatherConditionFromWmo(codes[i].toInt()),
          minC: minList[i].round(),
          maxC: maxList[i].round(),
        ),
    ];

    return WeatherForecast(
      condition: weatherConditionFromWmo(currentCode),
      currentC: currentC,
      feelsLikeC: feelsLikeC,
      minC: days.first.minC,
      maxC: days.first.maxC,
      fetchedAt: DateTime.now(),
      days: days,
    );
  }
}

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(Dio());
});
