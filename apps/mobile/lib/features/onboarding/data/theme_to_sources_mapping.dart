/// Mapping Thème → Sources CURATED recommandées
/// Utilisé pour la pré-sélection automatique des sources dans l'onboarding.
///
/// Basé sur l'analyse de sources_master.csv :
/// - Sources avec status = CURATED
/// - Classées par thème principal
/// - Max 5 sources par thème pour ne pas surcharger
///
/// Note: Les noms doivent correspondre EXACTEMENT à ceux de la base de données.
class ThemeToSourcesMapping {
  /// Mapping Thème slug → Noms des sources recommandées (max 5 par thème)
  static const Map<String, List<String>> byTheme = {
    'tech': [
      'ScienceEtonnante',
      'Epsiloon',
      'Monsieur Bidouille',
      'TechTrash',
      'Socialter',
    ],
    'international': [
      'Le Dessous des Cartes',
      'Le Collimateur',
      'Le Grand Continent',
      'Politico Europe',
      'Le Monde Diplomatique',
    ],
    'science': [
      'ScienceEtonnante',
      'La Science CQFD',
      'Epsiloon',
      'The Conversation',
    ],
    'culture': [
      'Le 1 Hebdo',
      'Philosophie Magazine',
      'The Conversation',
      'Revue Commentaire',
    ],
    'politics': [
      'Le Monde',
      'Mediapart',
      'Le Figaro',
      'Politico Europe',
      'Le Canard Enchaîné',
    ],
    'society': [
      'Les Pieds sur Terre',
      'Transfert',
      'France Info',
      'France Inter',
      'Blast',
    ],
    'environment': [
      'Bon Pote',
      'Reporterre',
      'Sismique',
    ],
    'economy': [
      'Heu?reka',
      'Alternatives Économiques',
      'Nouveau Départ',
      'Guerres de Business',
      'Les Échos',
    ],
  };

  /// Mapping optionnel Subtopic slug → Noms des sources spécialisées
  /// Pour raffiner la recommandation si l'utilisateur a choisi des sous-thèmes
  static const Map<String, List<String>> bySubtopic = {
    // Tech subtopics
    'ai': ['ScienceEtonnante', 'Epsiloon'],
    'cybersecurity': ['TechTrash'],
    'startups': ['TechTrash', 'Socialter'],

    // International subtopics
    'geopolitics': [
      'Le Dessous des Cartes',
      'Le Collimateur',
      'Le Grand Continent'
    ],
    'europe': ['Politico Europe', 'Le Grand Continent'],
    'usa': ['Courrier International'],
    'middle-east': ['Le Collimateur', 'Le Monde Diplomatique'],
    'asia': ['Le Dessous des Cartes'],

    // Science subtopics
    'physics': ['ScienceEtonnante', 'Epsiloon'],
    'biology': ['Epsiloon', 'The Conversation'],
    'space': ['ScienceEtonnante', 'Epsiloon'],
    'health': ['The Conversation'],

    // Culture subtopics
    'philosophy': ['Philosophie Magazine', 'Le 1 Hebdo'],
    'history': ['Le Dessous des Cartes', 'The Conversation'],
    'arts': ['Le 1 Hebdo'],

    // Politics subtopics
    'french-politics': ['Le Monde', 'Mediapart', 'Le Figaro'],
    'elections': ['Politico Europe', 'Le Monde'],

    // Society subtopics
    'social-justice': ['Mediapart', 'Libération', 'Blast'],
    'education': ['The Conversation', 'France Inter'],
    'media': ['Mécaniques du Complot', 'Blast'],

    // Environment subtopics
    'climate': ['Bon Pote', 'Reporterre', 'Sismique'],
    'biodiversity': ['Reporterre'],
    'energy': ['Sismique', 'Bon Pote'],

    // Economy subtopics
    'finance': ['Heu?reka', 'Les Échos', 'Guerres de Business'],
    'labor': ['Alternatives Économiques'],
    'macroeconomics': ['Heu?reka', 'Nouveau Départ'],
  };

  /// Calcule les sources recommandées en fonction des thèmes et sous-thèmes sélectionnés.
  ///
  /// [selectedThemes] - Liste des slugs de thèmes sélectionnés (ex: ['tech', 'science'])
  /// [selectedSubtopics] - Liste des slugs de sous-thèmes sélectionnés (ex: ['ai', 'climate'])
  ///
  /// Retourne un Set de noms de sources recommandées (max 15).
  static Set<String> computeRecommendedSources({
    required List<String> selectedThemes,
    List<String>? selectedSubtopics,
  }) {
    final Set<String> recommended = {};

    // 1. Ajouter les sources correspondant aux thèmes (max 5 par thème)
    for (final theme in selectedThemes) {
      final sourcesForTheme = byTheme[theme];
      if (sourcesForTheme != null) {
        recommended.addAll(sourcesForTheme.take(5));
      }
    }

    // 2. Raffiner avec les sous-thèmes (max 3 par sous-thème)
    if (selectedSubtopics != null) {
      for (final subtopic in selectedSubtopics) {
        final sourcesForSubtopic = bySubtopic[subtopic];
        if (sourcesForSubtopic != null) {
          recommended.addAll(sourcesForSubtopic.take(3));
        }
      }
    }

    // 3. Limiter à 15 sources max pour ne pas surcharger l'UI
    if (recommended.length > 15) {
      return recommended.take(15).toSet();
    }

    return recommended;
  }
}
