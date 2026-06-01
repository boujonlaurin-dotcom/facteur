/// Localisation utilisée pour la météo. Stockée localement (Hive `settings`),
/// jamais envoyée au backend — la météo reste 100 % client.
class WeatherLocation {
  final double lat;
  final double lng;

  /// Libellé affiché ("Paris" par défaut, "Ma position" si device).
  final String label;

  /// `true` quand les coordonnées viennent du GPS de l'appareil (vs. le défaut
  /// Paris). Pilote l'affichage du CTA « Activer ma position » et la bannière.
  final bool isDeviceLocation;

  const WeatherLocation({
    required this.lat,
    required this.lng,
    required this.label,
    required this.isDeviceLocation,
  });

  /// Défaut hors géoloc : Paris.
  static const WeatherLocation paris = WeatherLocation(
    lat: 48.8566,
    lng: 2.3522,
    label: 'Paris',
    isDeviceLocation: false,
  );

  @override
  bool operator ==(Object other) =>
      other is WeatherLocation &&
      other.lat == lat &&
      other.lng == lng &&
      other.label == label &&
      other.isDeviceLocation == isDeviceLocation;

  @override
  int get hashCode => Object.hash(lat, lng, label, isDeviceLocation);
}
