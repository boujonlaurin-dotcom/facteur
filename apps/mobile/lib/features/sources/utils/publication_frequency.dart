/// Humanise la fréquence de publication d'une source pour la fiche v3.
///
/// Fonction **pure** : le chip horloge du header en dérive un libellé naturel
/// (« 70 articles par jour en moyenne », « quelques articles par semaine »…).
///
/// - [articles30d] : nombre d'articles publiés sur les 30 derniers jours
///   (= `articles_30d` du profil = somme des `theme_distribution`).
/// - [oldestContentAt] : date du plus ancien contenu connu (tout l'historique).
///   Clampe la fenêtre pour ne pas **sous-estimer** une source fraîche :
///   6 articles publiés en 3 jours → « quelques-uns/jour », pas « /mois ».
/// - [now] : injectable pour des tests déterministes (défaut `DateTime.now()`).
String humanizeFrequency(
  int articles30d,
  DateTime? oldestContentAt, {
  DateTime? now,
}) {
  if (articles30d <= 0) return 'peu actif';

  final reference = now ?? DateTime.now();

  // Fenêtre = 30 j, bornée par l'âge réel de la source (1..30) si connu.
  var windowDays = 30;
  if (oldestContentAt != null) {
    final age = reference.difference(oldestContentAt).inDays;
    windowDays = age < 1 ? 1 : (age > 30 ? 30 : age);
  }

  final perDay = articles30d / windowDays;

  if (perDay >= 10) {
    final rounded = _niceRound(perDay);
    return '$rounded articles par jour en moyenne';
  }
  if (perDay >= 1.5) return 'quelques articles par jour';
  if (perDay * 7 >= 1.5) return 'quelques articles par semaine';
  return 'quelques articles par mois';
}

/// Arrondi « joli » pour les gros volumes (lecture rapide, pas exacte).
int _niceRound(double perDay) {
  if (perDay >= 100) return (perDay / 50).round() * 50; // ~100, ~150, ~200…
  if (perDay >= 20) return (perDay / 10).round() * 10; // ~30, ~40…
  return perDay.round(); // 10..19 → valeur exacte
}
