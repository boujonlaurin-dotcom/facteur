import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../services/tournee_progress_service.dart';
import '../utils/morning_ritual_format.dart';

/// EPIC « Lettre du jour » — état du sélecteur de date de l'Essentiel.
///
/// La sélection pilote ce que le bloc Essentiel affiche : l'actu du jour
/// (`EditionToday`), une lettre passée (`EditionPastDay`, jusqu'à J-7) ou la
/// rétro agrégée `EditionWeek` (« Cette semaine »). Les sections « tournée »
/// restent live et ne sont rendues que pour `EditionToday`.
sealed class EditionSelection {
  const EditionSelection();

  /// Clé stable (cache mémoire + tests) : `'today'`, `'week'` ou `'YYYY-MM-DD'`.
  /// Sert aussi d'identité : deux sélections sont égales ssi leurs `key` le sont
  /// (un même jour re-sélectionné ne provoque donc pas de churn, quelle que soit
  /// l'heure portée par la date-nue).
  String get key;

  @override
  bool operator ==(Object other) =>
      other is EditionSelection && other.key == key;

  @override
  int get hashCode => key.hashCode;
}

/// Aujourd'hui — lu depuis `fluxContinuProvider` (0 réseau). Accord client /
/// serveur par construction : aucun `target_date` n'est envoyé (évite le piège
/// de la frontière 7h30 vs `today_paris` côté backend).
class EditionToday extends EditionSelection {
  const EditionToday();

  @override
  String get key => 'today';
}

/// Rétro agrégée « Cette semaine » — calculée côté client (aucun endpoint
/// dédié) par fan-out borné sur J-0…J-6.
class EditionWeek extends EditionSelection {
  const EditionWeek();

  @override
  String get key => 'week';
}

/// Une lettre d'un jour passé. [date] est une **date-nue** (minuit local) ;
/// l'égalité se fait sur le jour calendaire via [key].
class EditionPastDay extends EditionSelection {
  final DateTime date;

  const EditionPastDay(this.date);

  @override
  String get key => editionDayKey(date);
}

/// Profondeur du sélecteur = fenêtre de fallback backend
/// (`_HOTPATH_FALLBACK_DAYS` = 7). Au-delà, le backend ne sert plus rien.
const int kEditionMaxPastDays = 7;

/// Sélection courante de l'édition. Défaut = aujourd'hui (feed live complet).
final selectedEditionDateProvider =
    StateProvider<EditionSelection>((_) => const EditionToday());

/// Date-nue (minuit local) de l'édition « aujourd'hui », dérivée de la frontière
/// 7h30 du jour-tournée (`TourneeProgressService.dayKey`). Avant 7h30 c'est
/// encore l'édition de la veille — cohérent avec le backend (`today_paris`) et
/// le gate du rituel matinal. Helper **pur** ; `now` injectable pour les tests.
DateTime editionTodayDate({DateTime? now}) {
  // `dayKey` renvoie `YYYY-MM-DD` (étiquette de jour, déjà décalée à 7h30) →
  // `DateTime.parse` en fait une date-nue locale.
  return DateTime.parse(TourneeProgressService.dayKey(now ?? DateTime.now()));
}

/// Les [count] dates-nues précédant « aujourd'hui » (J-1, J-2, … J-[count]),
/// les plus récentes d'abord. Construction par composantes (pas de
/// `subtract(Duration(days:))`) pour une arithmétique robuste aux frontières
/// DST. Source unique partagée par les pills et l'agrégation « Cette semaine ».
List<DateTime> editionPastDays(int count, {DateTime? now}) {
  final today = editionTodayDate(now: now);
  return [
    for (var i = 1; i <= count; i++)
      DateTime(today.year, today.month, today.day - i),
  ];
}

/// Modèle ordonné des pills du sélecteur, dans l'ordre exact d'affichage :
/// `[Cette semaine, Aujourd'hui, Hier, J-2 … J-7]`. Helper **pur** ; `now`
/// injectable pour les tests.
List<EditionSelection> editionPillModel({DateTime? now}) {
  return <EditionSelection>[
    const EditionWeek(),
    const EditionToday(),
    for (final date in editionPastDays(kEditionMaxPastDays, now: now))
      EditionPastDay(date),
  ];
}
