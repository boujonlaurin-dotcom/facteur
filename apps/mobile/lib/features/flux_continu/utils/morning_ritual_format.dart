import 'package:flutter/material.dart' show Color;

import '../../digest/models/digest_models.dart';
import '../models/flux_continu_models.dart';
import '../services/tournee_progress_service.dart';
import 'theme_color_mapping.dart';

/// Helpers **purs** (pas de provider, pas de réseau) du rituel matinal
/// (Story 28.1). Testables et déterministes.

/// L'édition du jour est-elle **réellement arrivée** ? Gate de révélation du
/// sommaire+CTA du rituel matinal. `now` injectable pour les tests.
///
/// **Source de vérité = le flux** (`fluxContinuProvider`, préchargé dès le boot
/// via `fluxContinuPreloadProvider`) : du contenu réel (`!isSkeleton`, sections
/// non vides) signifie l'édition du jour arrivée — son flag `isSkeleton`
/// garantit déjà « jamais du contenu d'hier » (décision PO #4).
///
/// Le `digest` n'est qu'une **corroboration optionnelle** : il est chargé
/// **séparément** (`digestProvider`, *non* préchargé) et vaut donc `null` les
/// premières secondes sur `/edition`. On ne bloque **jamais** dessus quand il
/// est absent (sinon le rituel ne se révèle jamais — bug E2E 24/06). Quand il
/// est là, il resserre la garantie de fraîcheur : on refuse un `isStaleFallback`
/// ou un `targetDate` qui ne tombe pas sur le jour-tournée courant.
bool isEditionReady(
  FluxContinuState? state,
  DigestResponse? digest, {
  DateTime? now,
}) {
  if (state == null || state.isSkeleton || state.sections.isEmpty) return false;
  if (digest != null) {
    if (digest.isStaleFallback) return false;
    final today = now ?? DateTime.now();
    // `targetDate` est une **étiquette éditoriale date-nue** (backend :
    // `str(today_paris())` → minuit local côté Dart). On compare son jour
    // **calendaire brut** (Y-M-D) au `dayKey` du jour-tournée — surtout PAS en
    // la repassant dans `dayKey()`, dont la bascule 7h30 retirerait un jour à
    // tout minuit (< 07h30) et rendrait le gate perpétuellement faux.
    if (editionDayKey(digest.targetDate) !=
        TourneeProgressService.dayKey(today)) {
      return false;
    }
  }
  return true;
}

/// Jour calendaire (`YYYY-MM-DD`) d'une `targetDate` éditoriale, à partir de ses
/// composantes brutes (aucune conversion tz : c'est un libellé, pas un instant).
String editionDayKey(DateTime date) {
  final mm = date.month.toString().padLeft(2, '0');
  final dd = date.day.toString().padLeft(2, '0');
  return '${date.year.toString().padLeft(4, '0')}-$mm-$dd';
}

/// Diagnostic **QA** (staging/dev) : pourquoi `isEditionReady` vaut ce qu'il
/// vaut. Listé condition par condition pour identifier d'un coup d'œil sur
/// l'appareil le maillon qui bloque (squelette ? digest absent ? mauvais jour ?).
String morningRitualReadinessDebug(
  FluxContinuState? state,
  DigestResponse? digest, {
  DateTime? now,
}) {
  final today = now ?? DateTime.now();
  // Source de vérité = le flux. Le digest est optionnel (« opt » s'il est null).
  final fluxOk = state != null && !state.isSkeleton && state.sections.isNotEmpty;
  final target = digest == null ? '∅' : editionDayKey(digest.targetDate);
  final todayKey = TourneeProgressService.dayKey(today);
  final String digestState;
  if (digest == null) {
    digestState = 'null(opt)';
  } else if (digest.isStaleFallback) {
    digestState = 'stale→bloque';
  } else if (target != todayKey) {
    digestState = 'jour-ko→bloque';
  } else {
    digestState = 'ok';
  }
  final ready = isEditionReady(state, digest, now: now);
  return 'ready=$ready · flux=${fluxOk ? "ok" : "ko"}'
      '(skel=${state?.isSkeleton}/sec=${state?.sections.length})'
      ' · digest=$digestState(t=$target/n=$todayKey)';
}

/// Libellé UI exact de La Grille dans le feed (`flux_continu_screen.dart`,
/// `StickyTab(label: 'Mot du jour')`). Réutilisé tel quel dans le sommaire pour
/// « reprendre le nom exact des sections » (décision PO 24/06).
const String kMotDuJourLabel = 'Mot du jour';

/// Accent neutre « loisir » de La Grille (= `_kLeisureTabAccent` du feed), porté
/// par la chip « Mot du jour » du sommaire (qui n'est pas une [FluxSection] et
/// n'a donc pas d'`accent` propre).
const Color kMotDuJourAccent = Color(0xFFB8A898);

/// Une entrée du sommaire « table des matières » de l'édition, rendue comme une
/// chip colorée dans le rituel matinal : libellé exact de la section + son
/// `accent` réel (cohérence avec le reste de l'app), et un flag [isVeille] pour
/// la chip spéciale « Ma veille » (étoile + accent `primary`).
class EditionSummaryEntry {
  final String label;
  final Color accent;
  final bool isVeille;

  const EditionSummaryEntry({
    required this.label,
    required this.accent,
    this.isVeille = false,
  });
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
List<EditionSummaryEntry> editionSummaryEntries(
  List<FluxSection> sections, {
  int? grilleSlotIndex,
  String motDuJourLabel = kMotDuJourLabel,
  Color motDuJourAccent = kMotDuJourAccent,
}) {
  final entries = <EditionSummaryEntry>[];
  for (var i = 0; i < sections.length; i++) {
    if (grilleSlotIndex == i) {
      entries.add(EditionSummaryEntry(
        label: motDuJourLabel,
        accent: motDuJourAccent,
      ));
    }
    final section = sections[i];
    if (section is EssentielSection) continue; // héros = titre de bloc
    entries.add(EditionSummaryEntry(
      label: section.label,
      accent: section.accent,
      isVeille: section.kind == SectionKind.veille,
    ));
  }
  // La Grille peut être ancrée tout en bas (après la dernière section).
  if (grilleSlotIndex == sections.length) {
    entries.add(EditionSummaryEntry(
      label: motDuJourLabel,
      accent: motDuJourAccent,
    ));
  }
  return entries;
}

/// Sommaire d'une édition **passée / hebdo** dérivé directement des `topics` de
/// `editionEssentielProvider` (EPIC « Lettre du jour » — carrousel de lettres).
///
/// Variante de [editionSummaryEntries] pour les cartes voisines du carrousel,
/// qui n'ont pas de [FluxSection] live : chaque [DigestTopic] devient une chip,
/// `label` verbatim, `accent` mappé depuis son `theme` via [themeMap] (fallback
/// neutre via [themeVisualFor] pour un thème inconnu/absent). Pas de chip veille
/// ni de « Mot du jour » (propres au feed live d'aujourd'hui).
List<EditionSummaryEntry> editionSummaryEntriesFromTopics(
  List<DigestTopic> topics,
) {
  return [
    for (final topic in topics)
      EditionSummaryEntry(
        label: topic.label,
        // `theme` peut être null → fallback neutre « Veille » de [visualFor].
        accent: visualFor(topic.theme ?? '').accent,
      ),
  ];
}
