/// Humanise la fréquence de publication d'une source pour la fiche v3.
///
/// Fonction **pure** : le chip horloge du header en dérive un libellé naturel
/// (« 70 articles par jour en moyenne », « quelques articles par semaine »…).
///
/// - [articles30d] : nombre d'articles **publiés** sur les 30 derniers jours
///   (= `articles_30d` du profil, tous thèmes confondus, y compris les non
///   classés). Peut donc dépasser la somme des `theme_distribution`, qui ne
///   couvre que les articles classés (frais non encore classé exclu des barres,
///   mais bien compté dans le volume/fréquence ici).
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

  final perDay = _perDay(articles30d, oldestContentAt, now);

  if (perDay >= 10) {
    final rounded = _niceRound(perDay);
    return '$rounded articles par jour en moyenne';
  }
  if (perDay >= 1.5) return 'quelques articles par jour';
  if (perDay * 7 >= 1.5) return 'quelques articles par semaine';
  return 'quelques articles par mois';
}

/// Une source est « rare » si elle publie moins d'une fois par semaine.
///
/// C'est le seul critère d'éligibilité à la cloche « alerte source » : il rend
/// la fonctionnalité insensible au spam par construction. Miroir exact de
/// `is_rare_source` côté serveur (`app/services/source_alert_producer.py`), qui
/// reste l'arbitre — le client peut afficher un profil périmé.
///
/// `articles30d == 0` n'est **pas** éligible : sans preuve que la source
/// publie (flux cassé, source morte), la cloche ne sonnerait jamais.
bool isRareSource(
  int articles30d,
  DateTime? oldestContentAt, {
  DateTime? now,
}) {
  if (articles30d < 1) return false;
  return _perDay(articles30d, oldestContentAt, now) * 7 < 1.0;
}

/// Phrase de rareté affichée sous la cloche — dérivée des mêmes seuils.
///
/// Jamais une affirmation que les chiffres ne soutiennent pas : la borne
/// d'éligibilité (< 1/semaine) garantit qu'on reste sur « deux semaines » ou
/// « mois ». Renvoie `null` si la source n'est pas rare, pour que l'appelant
/// ne puisse pas promettre une cadence qu'il ne tiendra pas.
String? rarityPhrase(
  int articles30d,
  DateTime? oldestContentAt, {
  DateTime? now,
}) {
  if (!isRareSource(articles30d, oldestContentAt, now: now)) return null;
  final perWeek = _perDay(articles30d, oldestContentAt, now) * 7;
  if (perWeek >= 0.5) return 'environ une fois toutes les deux semaines';
  return 'environ une fois par mois';
}

/// Volume quotidien moyen sur une fenêtre de 30 j bornée par l'âge réel de la
/// source. Base partagée de [humanizeFrequency] et [isRareSource] : les deux
/// doivent lire la même cadence, sinon la fiche affiche « quelques articles
/// par mois » à côté d'une cloche refusée.
double _perDay(int articles30d, DateTime? oldestContentAt, DateTime? now) {
  var windowDays = 30;
  if (oldestContentAt != null) {
    final age = (now ?? DateTime.now()).difference(oldestContentAt).inDays;
    windowDays = age < 1 ? 1 : (age > 30 ? 30 : age);
  }
  return articles30d / windowDays;
}

/// Arrondi « joli » pour les gros volumes (lecture rapide, pas exacte).
int _niceRound(double perDay) {
  if (perDay >= 100) return (perDay / 50).round() * 50; // ~100, ~150, ~200…
  if (perDay >= 20) return (perDay / 10).round() * 10; // ~30, ~40…
  return perDay.round(); // 10..19 → valeur exacte
}
