import '../models/veille_config.dart';

/// Mock data alignée sur `config-flow.jsx` du design bundle.
class VeilleMockData {
  VeilleMockData._();

  static const List<VeilleTheme> themes = [
    VeilleTheme(
      id: 'ia-edu',
      label: 'IA & éducation',
      meta: '34 articles · 2 sem',
      iconKey: 'graduation-cap',
      hot: true,
    ),
    VeilleTheme(
      id: 'climat',
      label: 'Climat',
      meta: '52 articles · 2 sem',
      iconKey: 'leaf',
      hot: true,
    ),
    VeilleTheme(
      id: 'medias',
      label: 'Médias & info',
      meta: '21 articles · 2 sem',
      iconKey: 'newspaper',
    ),
    VeilleTheme(
      id: 'energie',
      label: 'Énergie',
      meta: '18 articles · 2 sem',
      iconKey: 'lightning',
    ),
    VeilleTheme(
      id: 'immig',
      label: 'Immigration',
      meta: '14 articles · 2 sem',
      iconKey: 'globe-hemisphere-west',
    ),
    VeilleTheme(
      id: 'sante',
      label: 'Hôpital & santé',
      meta: '11 articles · 2 sem',
      iconKey: 'first-aid-kit',
    ),
  ];

  static const List<VeilleTopic> presetTopics = [
    VeilleTopic(
      id: 't-eval',
      label: 'Évaluation des apprentissages',
      reason: 'présent dans 8 de tes lectures',
    ),
    VeilleTopic(
      id: 't-form',
      label: 'Formation des enseignants',
      reason: 'facteur structurel sous-couvert',
    ),
    VeilleTopic(
      id: 't-tools',
      label: 'Outils pédagogiques IA',
      reason: 'centre d\'intérêt récurrent',
    ),
    VeilleTopic(
      id: 't-tri',
      label: 'Triche & dissertations à l\'IA',
      reason: 'actualité régulière',
    ),
    VeilleTopic(
      id: 't-insp',
      label: 'INSPÉ & formation initiale',
      reason: 'rapport DEPP attendu',
    ),
    VeilleTopic(
      id: 't-ort',
      label: 'Outils d\'aide à l\'orthographe',
      reason: 'adoption en hausse au collège',
    ),
  ];

  static const List<VeilleTopic> suggestedTopics = [
    VeilleTopic(
      id: 'sub-dys',
      label: 'IA & accessibilité (dyslexie, troubles dys)',
      reason: 'angle peu couvert dans tes lectures',
    ),
    VeilleTopic(
      id: 'sub-poli',
      label: 'Politiques éducatives nationales',
      reason: 'complète l\'angle structurel',
    ),
    VeilleTopic(
      id: 'sub-gs',
      label: 'Universités du Sud global',
      reason: 'perspective non-occidentale absente',
    ),
    VeilleTopic(
      id: 'sub-eth',
      label: 'Éthique & souveraineté des modèles',
      reason: 'élargit ta veille IA',
    ),
    VeilleTopic(
      id: 'sub-ent',
      label: 'IA & monde du travail',
      reason: 'connexe à l\'éducation',
    ),
  ];

  static const List<VeilleSource> followedSources = [
    VeilleSource(
      id: 's-lm',
      letter: 'M',
      name: 'Le Monde — Éducation',
      meta: 'Source suivie',
      editorialMeta: 'Quotidien généraliste · rubrique Éducation',
      biasStance: 'center-left',
      logoUrl:
          'https://www.google.com/s2/favicons?sz=128&domain=lemonde.fr',
    ),
    VeilleSource(
      id: 's-cp',
      letter: 'C',
      name: 'Café pédagogique',
      meta: 'Source suivie',
      editorialMeta: 'Média indépendant · enseignants & politiques scolaires',
      biasStance: 'center-left',
      logoUrl:
          'https://www.google.com/s2/favicons?sz=128&domain=cafepedagogique.net',
    ),
    VeilleSource(
      id: 's-tc',
      letter: 'T',
      name: 'The Conversation FR',
      meta: 'Source suivie',
      editorialMeta: 'Articles écrits par des chercheurs',
      biasStance: 'neutral',
      logoUrl:
          'https://www.google.com/s2/favicons?sz=128&domain=theconversation.com',
    ),
  ];

  static const List<VeilleSource> nicheSources = [
    VeilleSource(
      id: 's-ife',
      letter: 'IFÉ',
      name: 'Veille & Analyses IFÉ',
      editorialMeta: 'Institut français de l\'Éducation · ENS Lyon',
      biasStance: 'neutral',
      logoUrl: 'https://www.google.com/s2/favicons?sz=128&domain=ife.ens-lyon.fr',
      why:
          'recherche académique FR — la référence sur les politiques éducatives',
    ),
    VeilleSource(
      id: 's-eds',
      letter: 'ES',
      name: 'EdSurge',
      editorialMeta: 'Média US · innovations EdTech',
      biasStance: 'neutral',
      logoUrl: 'https://www.google.com/s2/favicons?sz=128&domain=edsurge.com',
      why: 'veille tech-edu pointue, lecture des innovations US',
    ),
    VeilleSource(
      id: 's-bsf',
      letter: 'BSF',
      name: 'Bibliothèque sans frontières',
      editorialMeta: 'ONG · accès à l\'éducation',
      biasStance: 'unknown',
      logoUrl:
          'https://www.google.com/s2/favicons?sz=128&domain=bibliosansfrontieres.org',
      why: 'terrain ONG — couvre le Sud global et l\'inclusion',
    ),
    VeilleSource(
      id: 's-aoc',
      letter: 'AOC',
      name: 'AOC media',
      editorialMeta: 'Quotidien d\'idées · essais & analyses',
      biasStance: 'left',
      logoUrl: 'https://www.google.com/s2/favicons?sz=128&domain=aoc.media',
      why: 'essais critiques — pose les enjeux politiques',
    ),
    VeilleSource(
      id: 's-dep',
      letter: 'D',
      name: 'DEPP — études MEN',
      editorialMeta: 'Direction stat. du ministère de l\'Éducation',
      biasStance: 'neutral',
      logoUrl:
          'https://www.google.com/s2/favicons?sz=128&domain=education.gouv.fr',
      why: 'données officielles, taux et statistiques',
    ),
    VeilleSource(
      id: 's-ths',
      letter: 'TH',
      name: 'Times Higher Education',
      editorialMeta: 'Magazine UK · enseignement supérieur',
      biasStance: 'neutral',
      logoUrl:
          'https://www.google.com/s2/favicons?sz=128&domain=timeshighereducation.com',
      why: 'perspective internationale enseignement supérieur',
    ),
  ];

  static const String defaultTheme = 'ia-edu';
  static const Set<String> defaultTopics = {'t-eval', 't-form'};
  static const Set<String> defaultSuggestions = {'sub-dys', 'sub-gs'};
  static const Set<String> defaultFollowedSources = {'s-lm', 's-cp', 's-tc'};
  static const Set<String> defaultNicheSources = {'s-ife', 's-bsf', 's-eds'};

  static const String recapTitle = 'L\'IA générative et l\'éducation';
}
