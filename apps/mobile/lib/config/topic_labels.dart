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
/// Used by MyInterestsScreen and TopicExplorerSheet to group topics.
const Map<String, String> _slugToMacroTheme = {
  // Tech & Science
  'ai': 'Tech & Science',
  'tech': 'Tech & Science',
  'cybersecurity': 'Tech & Science',
  'gaming': 'Tech & Science',
  'space': 'Tech & Science',
  'science': 'Tech & Science',
  'privacy': 'Tech & Science',
  // Societe
  'politics': 'Societe',
  'economy': 'Societe',
  'work': 'Societe',
  'education': 'Societe',
  'health': 'Societe',
  'justice': 'Societe',
  'immigration': 'Societe',
  'inequality': 'Societe',
  'feminism': 'Societe',
  'lgbtq': 'Societe',
  'religion': 'Societe',
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
  // Lifestyle
  'travel': 'Lifestyle',
  'gastronomy': 'Lifestyle',
  'sport': 'Lifestyle',
  'wellness': 'Lifestyle',
  'family': 'Lifestyle',
  'relationships': 'Lifestyle',
  // Business
  'startups': 'Business',
  'finance': 'Business',
  'realestate': 'Business',
  'entrepreneurship': 'Business',
  'marketing': 'Business',
  // International
  'geopolitics': 'International',
  'europe': 'International',
  'usa': 'International',
  'africa': 'International',
  'asia': 'International',
  'middleeast': 'International',
  // Autres
  'history': 'Autres',
  'philosophy': 'Autres',
  'factcheck': 'Autres',
};

/// Ordered list of macro-theme group labels.
const List<String> macroThemeOrder = [
  'Tech & Science',
  'Societe',
  'Environnement',
  'Culture',
  'Lifestyle',
  'Business',
  'International',
  'Autres',
];

/// Returns the macro-theme group label for a topic slug, or null if unknown.
String? getTopicMacroTheme(String slug) {
  return _slugToMacroTheme[slug.toLowerCase()];
}
