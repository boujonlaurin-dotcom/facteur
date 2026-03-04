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
};

/// Retourne le label français pour un slug de topic ML.
/// Fallback : capitalise le slug si inconnu.
String getTopicLabel(String slug) {
  return topicSlugToLabel[slug.toLowerCase()] ??
      (slug.isNotEmpty ? slug[0].toUpperCase() + slug.substring(1) : slug);
}

/// Mapping slug → macro-theme group label.
/// Aligné sur TOPIC_TO_THEME du backend (topic_theme_mapper.py).
/// Source de vérité : packages/api/app/services/ml/topic_theme_mapper.py
const Map<String, String> _slugToMacroTheme = {
  // Tech
  'ai': 'Tech',
  'tech': 'Tech',
  'cybersecurity': 'Tech',
  'gaming': 'Tech',
  'privacy': 'Tech',
  // Science
  'space': 'Science',
  'science': 'Science',
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
  // International
  'geopolitics': 'International',
  'europe': 'International',
  'usa': 'International',
  'africa': 'International',
  'asia': 'International',
  'middleeast': 'International',
  // Sport
  'sport': 'Sport',
};

/// Ordered list of macro-theme group labels (9 thèmes backend).
const List<String> macroThemeOrder = [
  'Tech',
  'Science',
  'Société',
  'Politique',
  'Économie',
  'Environnement',
  'Culture',
  'International',
  'Sport',
];

/// Returns the macro-theme group label for a topic slug, or null if unknown.
String? getTopicMacroTheme(String slug) {
  return _slugToMacroTheme[slug.toLowerCase()];
}
