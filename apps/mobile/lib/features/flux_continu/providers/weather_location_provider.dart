import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../models/weather_location.dart';

/// Source de vérité (locale) pour la localisation météo.
///
/// Défaut Paris. Charge/persiste dans la box Hive `settings`. La météo n'est
/// jamais géolocalisée à l'onboarding : `useDeviceLocation()` est déclenché par
/// la bannière in-feed (cf. `geoloc_prompt_provider.dart`). Le
/// [weatherProvider] watch ce provider → refetch automatique au changement.
class WeatherLocationNotifier extends Notifier<WeatherLocation> {
  static const _boxName = 'settings';
  static const _kLat = 'weather_loc_lat';
  static const _kLng = 'weather_loc_lng';
  static const _kLabel = 'weather_loc_label';
  static const _kIsDevice = 'weather_loc_is_device';

  @override
  WeatherLocation build() {
    unawaited(_loadFromHive());
    return WeatherLocation.paris;
  }

  Future<void> _loadFromHive() async {
    try {
      final box = await Hive.openBox<dynamic>(_boxName);
      final lat = box.get(_kLat);
      final lng = box.get(_kLng);
      if (lat is num && lng is num) {
        state = WeatherLocation(
          lat: lat.toDouble(),
          lng: lng.toDouble(),
          label: box.get(_kLabel, defaultValue: 'Ma position') as String,
          isDeviceLocation: box.get(_kIsDevice, defaultValue: true) as bool,
        );
      }
    } catch (e) {
      // Hive peut ne pas être initialisé (tests) → on garde le défaut Paris.
      debugPrint('WeatherLocation: load from Hive failed: $e');
    }
  }

  /// Demande la permission de localisation puis bascule sur la position du
  /// device. Retourne `true` si la position a été obtenue et persistée, `false`
  /// si refus/erreur (l'état reste alors sur Paris).
  Future<bool> useDeviceLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        return false;
      }
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.low,
        ),
      );
      final location = WeatherLocation(
        lat: position.latitude,
        lng: position.longitude,
        label: 'Ma position',
        isDeviceLocation: true,
      );
      state = location;
      await _persist(location);
      return true;
    } catch (e) {
      debugPrint('WeatherLocation: useDeviceLocation failed: $e');
      return false;
    }
  }

  Future<void> _persist(WeatherLocation location) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.putAll({
      _kLat: location.lat,
      _kLng: location.lng,
      _kLabel: location.label,
      _kIsDevice: location.isDeviceLocation,
    });
  }
}

final weatherLocationProvider =
    NotifierProvider<WeatherLocationNotifier, WeatherLocation>(
  WeatherLocationNotifier.new,
);
