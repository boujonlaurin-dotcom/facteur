import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/weather_snapshot.dart';
import '../repositories/weather_repository.dart';

const Duration _kWeatherTtl = Duration(minutes: 30);

class WeatherNotifier extends AsyncNotifier<WeatherSnapshot> {
  WeatherSnapshot? _cached;

  @override
  Future<WeatherSnapshot> build() async {
    final cached = _cached;
    if (cached != null &&
        DateTime.now().difference(cached.fetchedAt) < _kWeatherTtl) {
      return cached;
    }
    final fresh = await ref.read(weatherRepositoryProvider).fetchParis();
    _cached = fresh;
    return fresh;
  }
}

final weatherProvider =
    AsyncNotifierProvider<WeatherNotifier, WeatherSnapshot>(WeatherNotifier.new);
