import '../features/custom_topics/models/topic_models.dart';

/// Mapping des slugs de topics ML vers les labels français lisibles.
///
/// Miroir inversé de ClassificationService.LABEL_TO_SLUG (Python).
/// Source de vérité : packages/api/app/services/ml/classification_service.py
const Map<String, String> topicSlugToLabel = {
  // Tech & Science
  'ai': 'Intelligence artificielle',
  'tech': 'Technologie',
  'cybersecurity': 'Cybersécurité',
  'gaming': 'Jeux vidéo',
  'space': 'Espace et astronomie',
  'science': 'Science',
  'privacy': 'Données et vie privée',
  // Société
  'politics': 'Politique',
  'economy': 'Économie',
  'work': 'Emploi et travail',
  'education': 'Éducation',
  'health': 'Santé',
  'justice': 'Justice et droit',
  'immigration': 'Immigration',
  'inequality': 'Inégalités sociales',
  'feminism': 'Féminisme',
  'lgbtq': 'LGBTQ+',
  'religion': 'Religion',
  // Environnement
  'climate': 'Climat',
  'environment': 'Environnement',
  'energy': 'Énergie',
  'biodiversity': 'Biodiversité',
  'agriculture': 'Agriculture',
  'food': 'Alimentation',
  // Culture
  'cinema': 'Cinéma',
  'music': 'Musique',
  'literature': 'Littérature',
  'art': 'Art',
  'media': 'Médias',
  'fashion': 'Mode',
  'design': 'Design',
  // Lifestyle
  'travel': 'Voyage',
  'gastronomy': 'Gastronomie',
  'sport': 'Sport',
  'wellness': 'Bien-être',
  'family': 'Famille et parentalité',
  'relationships': 'Relations et amour',
  // Business
  'startups': 'Startups',
  'finance': 'Finance',
  'realestate': 'Immobilier',
  'entrepreneurship': 'Entrepreneuriat',
  'marketing': 'Marketing',
  // International
  'geopolitics': 'Géopolitique',
  'europe': 'Europe',
  'usa': 'États-Unis',
  'africa': 'Afrique',
  'asia': 'Asie',
  'middleeast': 'Moyen-Orient',
  // Autres
  'history': 'Histoire',
  'philosophy': 'Philosophie',
  'factcheck': 'Fact-checking',
  // Macro-theme slugs (used as source.theme in DB)
  'society': 'Société',
  'society_climate': 'Société',
  'culture_ideas': 'Culture & Idées',
  'international': 'International',
};

/// Retourne le label français pour un slug de topic ML.
/// Fallback : capitalise le slug si inconnu.
String getTopicLabel(String slug) {
  return topicSlugToLabel[slug.toLowerCase()] ??
      (slug.isNotEmpty ? slug[0].toUpperCase() + slug.substring(1) : slug);
}

/// Mapping slug → macro-theme group label.
/// Mirrors backend's TOPIC_TO_THEME (topic_theme_mapper.py).
/// Labels match feed filter bar (_themeMetadata in theme_filters_provider.dart).
const Map<String, String> _slugToMacroTheme = {
  // Technologie
  'ai': 'Technologie',
  'tech': 'Technologie',
  'cybersecurity': 'Technologie',
  'gaming': 'Technologie',
  'privacy': 'Technologie',
  // Sciences
  'space': 'Sciences',
  'science': 'Sciences',
  // Société
  'work': 'Société',
  'education': 'Société',
  'health': 'Société',
  'justice': 'Société',
  'immigration': 'Société',
  'inequality': 'Société',
  'feminism': 'Société',
  'lgbtq': 'Société',
  'religion': 'Société',
  'wellness': 'Société',
  'family': 'Société',
  'relationships': 'Société',
  'factcheck': 'Société',
  // Politique
  'politics': 'Politique',
  // Économie
  'economy': 'Économie',
  'startups': 'Économie',
  'finance': 'Économie',
  'realestate': 'Économie',
  'entrepreneurship': 'Économie',
  'marketing': 'Économie',
  // Environnement
  'climate': 'Environnement',
  'environment': 'Environnement',
  'energy': 'Environnement',
  'biodiversity': 'Environnement',
  'agriculture': 'Environnement',
  'food': 'Environnement',
  // Culture
  'cinema': 'Culture',
  'music': 'Culture',
  'literature': 'Culture',
  'art': 'Culture',
  'media': 'Culture',
  'fashion': 'Culture',
  'design': 'Culture',
  'travel': 'Culture',
  'gastronomy': 'Culture',
  'history': 'Culture',
  'philosophy': 'Culture',
  // Géopolitique
  'geopolitics': 'Géopolitique',
  'europe': 'Géopolitique',
  'usa': 'Géopolitique',
  'africa': 'Géopolitique',
  'asia': 'Géopolitique',
  'middleeast': 'Géopolitique',
  // Sport
  'sport': 'Sport',
};

/// Reverse mapping: macro-theme label → API theme slug.
/// Used to resolve the correct slug for algorithm profile lookups.
const Map<String, String> macroThemeToApiSlug = {
  'Technologie': 'tech',
  'Sciences': 'science',
  'Société': 'society',
  'Politique': 'politics',
  'Économie': 'economy',
  'Environnement': 'environment',
  'Culture': 'culture',
  'Géopolitique': 'international',
  'Sport': 'sport',
};

/// Ordered list of macro-theme group labels (matches backend's 9 themes).
const List<String> macroThemeOrder = [
  'Technologie',
  'Sciences',
  'Société',
  'Politique',
  'Économie',
  'Environnement',
  'Culture',
  'Géopolitique',
  'Sport',
];

/// Returns the macro-theme group label for a topic slug, or null if unknown.
String? getTopicMacroTheme(String slug) {
  return _slugToMacroTheme[slug.toLowerCase()];
}

/// Emoji for each macro-theme group label.
const Map<String, String> _macroThemeEmoji = {
  'Technologie': '💻',
  'Sciences': '🔬',
  'Société': '👥',
  'Politique': '🏛️',
  'Économie': '💰',
  'Environnement': '🌿',
  'Culture': '🎨',
  'Géopolitique': '🌍',
  'Sport': '⚽',
};

/// Returns the emoji for a macro-theme label, or empty string if unknown.
String getMacroThemeEmoji(String macroThemeLabel) {
  return _macroThemeEmoji[macroThemeLabel] ?? '';
}

/// Returns all topic slugs belonging to a given macro theme.
List<String> getSlugsForMacroTheme(String macroTheme) {
  return topicSlugToLabel.keys
      .where((slug) => getTopicMacroTheme(slug) == macroTheme)
      .toList();
}

/// Reverse lookup: finds a slug for a topic label from [topicSlugToLabel].
/// Returns the lowercased name if no slug match is found.
String getTopicSlug(String name) {
  final lower = name.toLowerCase();
  for (final entry in topicSlugToLabel.entries) {
    if (entry.value.toLowerCase() == lower) {
      return entry.key;
    }
  }
  return lower;
}

/// Converts entity type codes to French display labels.
String getEntityTypeLabel(String type) => switch (type.toUpperCase()) {
      'PERSON' => 'Personne',
      'ORG' => 'Organisation',
      'EVENT' => 'Événement',
      'LOCATION' => 'Lieu',
      'PRODUCT' => 'Produit',
      _ => type,
    };

/// Emoji for entity types (used in quick pick chips).
String getEntityTypeEmoji(String? entityType) =>
    switch (entityType?.toUpperCase()) {
      'PERSON' => '👤',
      'ORG' => '🏢',
      'LOCATION' => '📍',
      'EVENT' => '📅',
      'PRODUCT' => '📦',
      _ => '🏷️',
    };

/// Counts followed topics per macro-theme from an already-loaded list.
/// No extra API call — uses the same data from customTopicsProvider.
Map<String, int> countTopicsPerMacroTheme(List<UserTopicProfile> topics) {
  final counts = {for (final t in macroThemeOrder) t: 0};
  for (final topic in topics) {
    final macro = getTopicMacroTheme(topic.slugParent ?? '');
    if (macro != null && counts.containsKey(macro)) {
      counts[macro] = counts[macro]! + 1;
    }
  }
  return counts;
}
