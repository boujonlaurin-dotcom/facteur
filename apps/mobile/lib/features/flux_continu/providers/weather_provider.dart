import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather_snapshot.dart';
import '../repositories/weather_repository.dart';
import 'weather_location_provider.dart';

const Duration _kWeatherTtl = Duration(minutes: 30);

class WeatherNotifier extends AsyncNotifier<WeatherForecast> {
  WeatherForecast? _cached;
  String? _cachedKey;

  @override
  Future<WeatherForecast> build() async {
    // Refetch dès que la localisation change (Paris → device, etc.).
    final location = ref.watch(weatherLocationProvider);
    final key = '${location.lat},${location.lng}';

    final cached = _cached;
    if (cached != null &&
        _cachedKey == key &&
        DateTime.now().difference(cached.fetchedAt) < _kWeatherTtl) {
      return cached;
    }

    final fresh = await ref
        .read(weatherRepositoryProvider)
        .fetch(location.lat, location.lng);
    _cached = fresh;
    _cachedKey = key;
    return fresh;
  }
}

final weatherProvider =
    AsyncNotifierProvider<WeatherNotifier, WeatherForecast>(WeatherNotifier.new);
