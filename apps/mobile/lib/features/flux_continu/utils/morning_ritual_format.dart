// Helpers **purs** (pas de provider, pas de réseau) du rituel matinal
// (Story 28.1). Testables et déterministes.

/// Jour calendaire (`YYYY-MM-DD`) d'une `targetDate` éditoriale, à partir de ses
/// composantes brutes (aucune conversion tz : c'est un libellé, pas un instant).
String editionDayKey(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$mm-$dd';
}

const List<String> _frenchWeekdays = <String>[
  'lundi',
  'mardi',
  'mercredi',
  'jeudi',
  'vendredi',
  'samedi',
  'dimanche',
];

const List<String> _frenchMonths = <String>[
  'janvier',
  'février',
  'mars',
  'avril',
  'mai',
  'juin',
  'juillet',
  'août',
  'septembre',
  'octobre',
  'novembre',
  'décembre',
];

/// Date longue FR sans `intl`/locale globale (jamais initialisée dans l'app) :
/// « mercredi 27 mai ». `DateTime.weekday` vaut 1 (lundi) … 7 (dimanche).
String formatFrenchLongDate(DateTime date) {
  final weekday = _frenchWeekdays[(date.weekday - 1) % 7];
  final month = _frenchMonths[(date.month - 1) % 12];
  return '$weekday ${date.day} $month';
}

/// Libellé court FR « mar. 24 » (jour de semaine abrégé + numéro), dérivé des
/// [_frenchWeekdays] existants (3 lettres + point). Pour les pills du sélecteur
/// de date de l'Essentiel (EPIC « Lettre du jour »).
String formatFrenchShortWeekdayDay(DateTime date) {
  final short = _frenchWeekdays[(date.weekday - 1) % 7].substring(0, 3);
  return '$short. ${date.day}';
}
