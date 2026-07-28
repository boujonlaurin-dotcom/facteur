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

/// Rythme de parution en articles par semaine.
///
/// Miroir exact de `cadence_per_week` côté serveur
/// (`app/services/alert_cadence.py`), qui reste l'arbitre : le client peut
/// afficher un profil périmé.
double cadencePerWeek(
  int articles30d,
  DateTime? oldestContentAt, {
  DateTime? now,
}) =>
    _perDay(articles30d, oldestContentAt, now) * 7;

/// Au-delà de ce rythme, la cloche devient du bruit : on affiche un
/// avertissement et on pré-coche le mode filtré.
const double kNoisyPerWeek = 3.0;

/// Vrai si la cible publie assez pour que la cloche devienne du bruit.
bool isNoisy(int articles30d, DateTime? oldestContentAt, {DateTime? now}) =>
    isNoisyAt(cadencePerWeek(articles30d, oldestContentAt, now: now));

/// Variante prenant la cadence directement.
///
/// Les sujets n'ont pas d'« âge » exploitable côté client : le backend renvoie
/// leur cadence déjà calculée (`GET /personalization/topics/{id}/frequency`),
/// et la recalculer ici sur une fenêtre devinée ferait diverger le devis
/// affiché de celui qui gouverne réellement les envois.
bool isNoisyAt(double perWeek) => perWeek > kNoisyPerWeek;

/// Phrase de cadence affichée sous la cloche — le devis honnête qui a remplacé
/// le gate de rareté de la v1.
///
/// L'unité suit le rythme réel (mois → semaine → jour) pour que le chiffre
/// reste lisible : « 21 fois par semaine » ne se visualise pas, « environ 3 par
/// jour » si.
String cadencePhrase(
  int articles30d,
  DateTime? oldestContentAt, {
  DateTime? now,
}) =>
    cadencePhraseAt(cadencePerWeek(articles30d, oldestContentAt, now: now));

/// Variante prenant la cadence directement — cf. [isNoisyAt].
String cadencePhraseAt(double perWeek) {
  if (perWeek <= 0) return 'Publie rarement';
  if (perWeek < 0.5) return 'Publie environ une fois par mois';
  if (perWeek < 1.5) return 'Publie environ une fois par semaine';
  if (perWeek < kNoisyPerWeek) {
    return 'Publie environ ${perWeek.round()} fois par semaine';
  }
  final perDay = perWeek / 7;
  if (perDay < 1.5) return 'Publie environ une fois par jour';
  return 'Publie environ ${perDay.round()} fois par jour';
}

/// Devis de bruit affiché avant l'activation d'une cloche bruyante.
String expectedAlertsPhrase(
  int articles30d,
  DateTime? oldestContentAt, {
  DateTime? now,
}) =>
    expectedAlertsPhraseAt(
        cadencePerWeek(articles30d, oldestContentAt, now: now));

/// Variante prenant la cadence directement — cf. [isNoisyAt].
String expectedAlertsPhraseAt(double perWeek) {
  if (perWeek >= 7) {
    return 'Environ ${(perWeek / 7).round()} alertes par jour';
  }
  return 'Environ ${perWeek.round()} alertes par semaine';
}

/// Volume quotidien moyen sur une fenêtre de 30 j bornée par l'âge réel de la
/// source. Base partagée de [humanizeFrequency] et [cadencePerWeek] : les deux
/// doivent lire la même cadence, sinon le chip de fréquence contredirait le
/// devis de bruit affiché juste en dessous.
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
