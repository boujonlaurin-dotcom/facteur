import '../../digest/models/digest_models.dart';
import '../models/flux_continu_models.dart';
import '../services/tournee_progress_service.dart';

/// Helpers **purs** (pas de provider, pas de réseau) du rituel matinal
/// (Story 28.1). Testables et déterministes.

/// L'édition du jour est-elle **réellement arrivée** (pas du cache d'hier, pas
/// un squelette, pas un stale fallback) ? Gate de révélation du sommaire+CTA du
/// rituel matinal. `now` injectable pour les tests.
///
/// Conditions (décision PO #4 — jamais de fausse promesse « vient d'arriver ») :
/// - le flux a du contenu réel (`!isSkeleton`, sections non vides) ;
/// - le digest est présent, non périmé (`!isStaleFallback`) ;
/// - sa `targetDate` tombe sur le jour-tournée courant (`dayKey`, bascule 7h30) ;
/// - le digest porte du contenu (`topics` ou `items`).
bool isEditionReady(
  FluxContinuState? state,
  DigestResponse? digest, {
  DateTime? now,
}) {
  if (state == null || state.isSkeleton || state.sections.isEmpty) return false;
  if (digest == null || digest.isStaleFallback) return false;
  final today = now ?? DateTime.now();
  // `targetDate` est une **étiquette éditoriale date-nue** (backend :
  // `str(today_paris())` → minuit local côté Dart). On compare donc son jour
  // **calendaire brut** (Y-M-D) au `dayKey` du jour-tournée — surtout PAS en la
  // repassant dans `dayKey()`, dont la bascule 7h30 retirerait un jour à tout
  // minuit (< 07h30) et rendrait le gate perpétuellement faux.
  if (editionDayKey(digest.targetDate) !=
      TourneeProgressService.dayKey(today)) {
    return false;
  }
  return digest.topics.isNotEmpty || digest.items.isNotEmpty;
}

/// Jour calendaire (`YYYY-MM-DD`) d'une `targetDate` éditoriale, à partir de ses
/// composantes brutes (aucune conversion tz : c'est un libellé, pas un instant).
String editionDayKey(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// Libellé UI exact de La Grille dans le feed (`flux_continu_screen.dart`,
/// `StickyTab(label: 'Mot du jour')`). Réutilisé tel quel dans le sommaire pour
/// « reprendre le nom exact des sections » (décision PO 24/06).
const String kMotDuJourLabel = 'Mot du jour';

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

/// Sommaire « table des matières » de l'édition du jour : libellés **exacts** des
/// sections réellement affichées, dans l'ordre du feed (décision PO 24/06).
///
/// - libellé verbatim (`section.label`), aucun relabel ;
/// - le **héros** [EssentielSection] est exclu (c'est déjà le titre de bloc
///   « L'Essentiel du jour » au-dessus du sommaire) ;
/// - « Mot du jour » (La Grille) est inséré à [grilleSlotIndex] — la même
///   position absolue que le rendu du feed (`FluxContinuState.grilleSlotIndex`),
///   typiquement juste après « Actus du jour » ;
/// - les sections suggérées (« Choisie pour vous ») sont **incluses** (elles
///   s'affichent vraiment), avec leur libellé thème/source.
List<String> editionSummaryEntries(
  List<FluxSection> sections, {
  int? grilleSlotIndex,
  String motDuJourLabel = kMotDuJourLabel,
}) {
  final entries = <String>[];
  for (var i = 0; i < sections.length; i++) {
    if (grilleSlotIndex == i) entries.add(motDuJourLabel);
    final section = sections[i];
    if (section is EssentielSection) continue; // héros = titre de bloc
    entries.add(section.label);
  }
  // La Grille peut être ancrée tout en bas (après la dernière section).
  if (grilleSlotIndex == sections.length) entries.add(motDuJourLabel);
  return entries;
}
