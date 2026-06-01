import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/core/nudges/nudge_counters.dart';
import 'package:facteur/features/flux_continu/models/weather_location.dart';
import 'package:facteur/features/flux_continu/providers/geoloc_prompt_provider.dart';
import 'package:facteur/features/flux_continu/providers/weather_location_provider.dart';

/// Notifier de localisation factice : court-circuite le chargement Hive et
/// renvoie une localisation fixe.
class _FakeLocationNotifier extends WeatherLocationNotifier {
  _FakeLocationNotifier(this._location);
  final WeatherLocation _location;
  @override
  WeatherLocation build() => _location;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;

  setUp(() async {
    tempDir = Directory.systemTemp.createTempSync('geoloc_prompt_test');
    Hive.init(tempDir.path);
    // Box `settings` propre pour chaque test.
    final box = await Hive.openBox<dynamic>('settings');
    await box.clear();
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
    tempDir.deleteSync(recursive: true);
  });

  ProviderContainer makeContainer(WeatherLocation location) {
    final container = ProviderContainer(
      overrides: [
        weatherLocationProvider
            .overrideWith(() => _FakeLocationNotifier(location)),
      ],
    );
    addTearDown(container.dispose);
    return container;
  }

  final feedKey = 'nudge.counter.${NudgeCounters.feedOpenCount}';

  test('false below 5 feed opens', () async {
    SharedPreferences.setMockInitialValues({feedKey: 4});
    final container = makeContainer(WeatherLocation.paris);
    expect(
      await container.read(geolocPromptShouldShowProvider.future),
      isFalse,
    );
  });

  test('true at 5 feed opens (Paris default, no cap reached)', () async {
    SharedPreferences.setMockInitialValues({feedKey: 5});
    final container = makeContainer(WeatherLocation.paris);
    expect(
      await container.read(geolocPromptShouldShowProvider.future),
      isTrue,
    );
  });

  test('false when already on device location', () async {
    SharedPreferences.setMockInitialValues({feedKey: 10});
    final container = makeContainer(
      const WeatherLocation(
        lat: 1,
        lng: 2,
        label: 'Ma position',
        isDeviceLocation: true,
      ),
    );
    expect(
      await container.read(geolocPromptShouldShowProvider.future),
      isFalse,
    );
  });

  test('false when display cap is reached', () async {
    SharedPreferences.setMockInitialValues({feedKey: 10});
    final box = await Hive.openBox<dynamic>('settings');
    await box.put(
      GeolocPromptController.kShownCount,
      kGeolocPromptMaxShown,
    );
    final container = makeContainer(WeatherLocation.paris);
    expect(
      await container.read(geolocPromptShouldShowProvider.future),
      isFalse,
    );
  });

  test('false when permanently dismissed', () async {
    SharedPreferences.setMockInitialValues({feedKey: 10});
    final box = await Hive.openBox<dynamic>('settings');
    await box.put(GeolocPromptController.kDismissed, true);
    final container = makeContainer(WeatherLocation.paris);
    expect(
      await container.read(geolocPromptShouldShowProvider.future),
      isFalse,
    );
  });
}
