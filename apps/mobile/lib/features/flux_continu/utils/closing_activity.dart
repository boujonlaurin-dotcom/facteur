import '../models/weather_snapshot.dart';

/// Une suggestion d'activité tangible hors-écran proposée sur la carte de fin
/// de tournée — pour incarner le « moment de fermeture » plutôt que d'inviter
/// à rester dans l'app.
class ClosingActivity {
  /// Emoji d'accroche (📖, 🌳, …).
  final String emoji;

  /// Proposition à l'infinitif, tournée en question, qui complète le préfixe
  /// « Et si tu en profitais pour… » (« Tester une nouvelle recette ? »).
  final String prompt;

  /// Activité d'extérieur (éligible seulement quand la météo s'y prête).
  final bool isOutdoor;

  const ClosingActivity({
    required this.emoji,
    required this.prompt,
    required this.isOutdoor,
  });
}

/// Activités d'intérieur — toujours éligibles (par défaut quand la météo n'est
/// pas clémente ou inconnue).
const List<ClosingActivity> kIndoorActivities = [
  ClosingActivity(emoji: '📖', prompt: 'Ouvrir un bon livre ?', isOutdoor: false),
  ClosingActivity(
    emoji: '🍳',
    prompt: 'Tester une nouvelle recette ?',
    isOutdoor: false,
  ),
  ClosingActivity(
    emoji: '☕',
    prompt: 'Prendre un vrai temps calme ?',
    isOutdoor: false,
  ),
  ClosingActivity(
    emoji: '📓',
    prompt: 'Écrire trois lignes dans un carnet ?',
    isOutdoor: false,
  ),
  ClosingActivity(
    emoji: '🎧',
    prompt: 'Écouter l’album du moment en entier ?',
    isOutdoor: false,
  ),
];

/// Activités d'extérieur — éligibles seulement quand le ciel est dégagé.
const List<ClosingActivity> kOutdoorActivities = [
  ClosingActivity(
    emoji: '🌳',
    prompt: 'Aller marcher dans un parc ?',
    isOutdoor: true,
  ),
  ClosingActivity(emoji: '☀️', prompt: 'Sortir prendre l’air ?', isOutdoor: true),
  ClosingActivity(emoji: '🚲', prompt: 'Faire un tour à vélo ?', isOutdoor: true),
];

/// Nombre de propositions affichées chaque jour sur la carte de fin.
const int kClosingActivityCount = 3;

/// Choisit les [count] activités du jour. Rotation **déterministe** par jour de
/// l'année (sélection stable sur la journée, pas de jitter au rebuild) ; la
/// météo élargit seulement l'éventail. [condition] non clémente/null (météo en
/// cours/échec) → uniquement l'intérieur ; ciel dégagé → intérieur + extérieur.
///
/// Les propositions retournées sont **distinctes** (l'éventail éligible a
/// toujours ≥ [count] entrées puisque [kIndoorActivities] en compte assez).
List<ClosingActivity> pickClosingActivities({
  required WeatherCondition? condition,
  DateTime? now,
  int count = kClosingActivityCount,
}) {
  final d = now ?? DateTime.now();
  final dayOfYear = d.difference(DateTime(d.year)).inDays; // sans intl
  final outdoorOk = condition == WeatherCondition.sunny ||
      condition == WeatherCondition.partlyCloudy;
  // Intérieur d'abord pour garantir ≥ count éligibles même sans extérieur.
  final eligible = outdoorOk
      ? [...kIndoorActivities, ...kOutdoorActivities]
      : kIndoorActivities;

  final n = count.clamp(0, eligible.length);
  final start = eligible.isEmpty ? 0 : dayOfYear % eligible.length;
  return [
    for (var i = 0; i < n; i++) eligible[(start + i) % eligible.length],
  ];
}
