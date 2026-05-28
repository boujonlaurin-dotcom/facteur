import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather_snapshot.dart';

/// Open-Meteo public endpoint. No API key required, lat/lng pinned to Paris
/// for the MVP (no UI for city selection yet).
const String _kOpenMeteoUrl =
    'https://api.open-meteo.com/v1/forecast?latitude=48.8566&longitude=2.3522'
    '&current=temperature_2m,weather_code'
    '&daily=temperature_2m_max,temperature_2m_min'
    '&timezone=Europe/Paris&forecast_days=1';

class WeatherRepository {
  final Dio _dio;

  WeatherRepository(this._dio);

  Future<WeatherSnapshot> fetchParis() async {
    final response = await _dio.get<Map<String, dynamic>>(
      _kOpenMeteoUrl,
      options: Options(
        receiveTimeout: const Duration(seconds: 4),
        sendTimeout: const Duration(seconds: 4),
      ),
    );
    final data = response.data;
    if (data == null) {
      throw StateError('Open-Meteo returned an empty body');
    }
    final current = (data['current'] as Map).cast<String, dynamic>();
    final daily = (data['daily'] as Map).cast<String, dynamic>();
    final currentC = (current['temperature_2m'] as num).round();
    final code = (current['weather_code'] as num).toInt();
    final maxList = (daily['temperature_2m_max'] as List).cast<num>();
    final minList = (daily['temperature_2m_min'] as List).cast<num>();
    return WeatherSnapshot(
      condition: weatherConditionFromWmo(code),
      currentC: currentC,
      minC: minList.first.round(),
      maxC: maxList.first.round(),
      fetchedAt: DateTime.now(),
    );
  }
}

final weatherRepositoryProvider = Provider<WeatherRepository>((ref) {
  return WeatherRepository(Dio());
});
