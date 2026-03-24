import '../../custom_topics/models/topic_models.dart';

class SubtopicOption {
  final String slug;
  final String label;
  final String emoji;
  final bool isPopular;

  const SubtopicOption({
    required this.slug,
    required this.label,
    required this.emoji,
    this.isPopular = false,
  });
}

class AvailableSubtopics {
  static final Map<String, List<SubtopicOption>> byTheme = {
    'tech': [
      const SubtopicOption(
          slug: 'ai', label: 'Intelligence artificielle', emoji: '🤖', isPopular: true),
      const SubtopicOption(
          slug: 'tech', label: 'Technologie générale', emoji: '💻', isPopular: true),
      const SubtopicOption(
          slug: 'gaming', label: 'Jeux vidéo', emoji: '🎮', isPopular: true),
      const SubtopicOption(
          slug: 'cybersecurity', label: 'Cybersécurité', emoji: '🔒'),
      const SubtopicOption(
          slug: 'privacy', label: 'Données et vie privée', emoji: '🛡️'),
    ],
    'international': [
      const SubtopicOption(
          slug: 'europe', label: 'Europe', emoji: '🇪🇺', isPopular: true),
      const SubtopicOption(
          slug: 'usa', label: 'États-Unis', emoji: '🇺🇸', isPopular: true),
      const SubtopicOption(
          slug: 'geopolitics', label: 'Géopolitique', emoji: '🗺️', isPopular: true),
      const SubtopicOption(slug: 'asia', label: 'Asie', emoji: '🌏'),
      const SubtopicOption(
          slug: 'middleeast', label: 'Moyen-Orient', emoji: '🕌'),
      const SubtopicOption(
          slug: 'africa', label: 'Afrique', emoji: '🌍'),
    ],
    'science': [
      const SubtopicOption(
          slug: 'space', label: 'Espace et astronomie', emoji: '🚀', isPopular: true),
      const SubtopicOption(
          slug: 'health', label: 'Recherche médicale', emoji: '🧬', isPopular: true),
      const SubtopicOption(
          slug: 'environment', label: 'Sciences de la Terre', emoji: '🌍'),
      const SubtopicOption(
          slug: 'energy', label: 'Physique et énergie', emoji: '⚡'),
    ],
    'culture': [
      const SubtopicOption(
          slug: 'cinema', label: 'Cinéma', emoji: '🎬', isPopular: true),
      const SubtopicOption(
          slug: 'music', label: 'Musique', emoji: '🎵', isPopular: true),
      const SubtopicOption(
          slug: 'philosophy', label: 'Philosophie', emoji: '🤔', isPopular: true),
      const SubtopicOption(slug: 'history', label: 'Histoire', emoji: '📜'),
      const SubtopicOption(
          slug: 'gastronomy', label: 'Gastronomie', emoji: '🍽️'),
      const SubtopicOption(
          slug: 'literature', label: 'Littérature', emoji: '📚'),
      const SubtopicOption(slug: 'art', label: 'Art', emoji: '🖼️'),
      const SubtopicOption(slug: 'travel', label: 'Voyage', emoji: '✈️'),
      const SubtopicOption(slug: 'media', label: 'Médias', emoji: '📺'),
    ],
    'politics': [
      const SubtopicOption(
          slug: 'politics', label: 'Politique intérieure', emoji: '🏛️', isPopular: true),
      const SubtopicOption(
          slug: 'geopolitics', label: 'Géopolitique', emoji: '🗺️', isPopular: true),
      const SubtopicOption(
          slug: 'factcheck', label: 'Fact-checking', emoji: '✅'),
      const SubtopicOption(
          slug: 'justice', label: 'Justice', emoji: '⚖️'),
    ],
    'society': [
      const SubtopicOption(
          slug: 'justice', label: 'Justice et droit', emoji: '⚖️', isPopular: true),
      const SubtopicOption(
          slug: 'health', label: 'Santé', emoji: '🩺', isPopular: true),
      const SubtopicOption(
          slug: 'education', label: 'Éducation', emoji: '🎓', isPopular: true),
      const SubtopicOption(
          slug: 'work', label: 'Emploi et travail', emoji: '💼'),
      const SubtopicOption(
          slug: 'immigration', label: 'Immigration', emoji: '🌐'),
      const SubtopicOption(
          slug: 'inequality', label: 'Inégalités', emoji: '📊'),
      const SubtopicOption(
          slug: 'feminism', label: 'Féminisme', emoji: '♀️'),
      const SubtopicOption(
          slug: 'lgbtq', label: 'LGBTQ+', emoji: '🏳️‍🌈'),
      const SubtopicOption(
          slug: 'religion', label: 'Religion', emoji: '🕊️'),
      const SubtopicOption(
          slug: 'family', label: 'Famille', emoji: '👨‍👩‍👧‍👦'),
    ],
    'environment': [
      const SubtopicOption(
          slug: 'climate', label: 'Climat', emoji: '🌡️', isPopular: true),
      const SubtopicOption(
          slug: 'energy', label: 'Énergie', emoji: '⚡', isPopular: true),
      const SubtopicOption(
          slug: 'biodiversity', label: 'Biodiversité', emoji: '🐾'),
      const SubtopicOption(
          slug: 'agriculture', label: 'Agriculture', emoji: '🌾'),
      const SubtopicOption(
          slug: 'food', label: 'Alimentation', emoji: '🥗'),
    ],
    'economy': [
      const SubtopicOption(
          slug: 'finance', label: 'Finance', emoji: '💰', isPopular: true),
      const SubtopicOption(
          slug: 'startups', label: 'Startups', emoji: '🦄', isPopular: true),
      const SubtopicOption(
          slug: 'entrepreneurship', label: 'Entrepreneuriat', emoji: '💡'),
      const SubtopicOption(
          slug: 'realestate', label: 'Immobilier', emoji: '🏠'),
      const SubtopicOption(
          slug: 'marketing', label: 'Marketing', emoji: '📣'),
    ],
    'sport': [
      const SubtopicOption(
          slug: 'wellness', label: 'Bien-être sportif', emoji: '🧘', isPopular: true),
      const SubtopicOption(
          slug: 'health', label: 'Santé et performance', emoji: '💪', isPopular: true),
    ],
  };

  /// Entités par défaut affichées quand le backend n'en retourne pas (ou en complément).
  static const Map<String, List<PopularEntity>> defaultEntities = {
    'tech': [
      PopularEntity(name: 'OpenAI', type: 'ORG', theme: 'tech'),
      PopularEntity(name: 'Apple', type: 'ORG', theme: 'tech'),
      PopularEntity(name: 'Réseaux sociaux', type: 'TOPIC', theme: 'tech'),
      PopularEntity(name: 'Blockchain', type: 'TOPIC', theme: 'tech'),
      PopularEntity(name: 'Cloud computing', type: 'TOPIC', theme: 'tech'),
    ],
    'science': [
      PopularEntity(name: 'Physique', type: 'TOPIC', theme: 'science'),
      PopularEntity(name: 'Mathématiques', type: 'TOPIC', theme: 'science'),
      PopularEntity(name: 'Astrophysique', type: 'TOPIC', theme: 'science'),
      PopularEntity(name: 'Chimie', type: 'TOPIC', theme: 'science'),
      PopularEntity(name: 'Biologie', type: 'TOPIC', theme: 'science'),
      PopularEntity(name: 'NASA', type: 'ORG', theme: 'science'),
    ],
    'sport': [
      PopularEntity(name: 'Football', type: 'TOPIC', theme: 'sport'),
      PopularEntity(name: 'Basketball', type: 'TOPIC', theme: 'sport'),
      PopularEntity(name: 'Tennis', type: 'TOPIC', theme: 'sport'),
      PopularEntity(name: 'Rugby', type: 'TOPIC', theme: 'sport'),
      PopularEntity(name: 'Formule 1', type: 'TOPIC', theme: 'sport'),
      PopularEntity(name: 'JO 2028', type: 'EVENT', theme: 'sport'),
    ],
    'politics': [
      PopularEntity(name: 'Assemblée nationale', type: 'ORG', theme: 'politics'),
      PopularEntity(name: 'Union européenne', type: 'ORG', theme: 'politics'),
      PopularEntity(name: 'Élections', type: 'TOPIC', theme: 'politics'),
      PopularEntity(name: 'Réforme des retraites', type: 'TOPIC', theme: 'politics'),
    ],
    'society': [
      PopularEntity(name: 'Réforme éducation', type: 'TOPIC', theme: 'society'),
      PopularEntity(name: 'Système de santé', type: 'TOPIC', theme: 'society'),
      PopularEntity(name: 'Droits des femmes', type: 'TOPIC', theme: 'society'),
      PopularEntity(name: 'Logement', type: 'TOPIC', theme: 'society'),
    ],
    'culture': [
      PopularEntity(name: 'Festival de Cannes', type: 'EVENT', theme: 'culture'),
      PopularEntity(name: 'Studio Ghibli', type: 'ORG', theme: 'culture'),
      PopularEntity(name: 'Hip-hop', type: 'TOPIC', theme: 'culture'),
      PopularEntity(name: 'Manga', type: 'TOPIC', theme: 'culture'),
      PopularEntity(name: 'Séries TV', type: 'TOPIC', theme: 'culture'),
    ],
    'economy': [
      PopularEntity(name: 'CAC 40', type: 'ORG', theme: 'economy'),
      PopularEntity(name: 'Inflation', type: 'TOPIC', theme: 'economy'),
      PopularEntity(name: 'Cryptomonnaies', type: 'TOPIC', theme: 'economy'),
      PopularEntity(name: 'Marché immobilier', type: 'TOPIC', theme: 'economy'),
    ],
    'environment': [
      PopularEntity(name: 'Nucléaire', type: 'TOPIC', theme: 'environment'),
      PopularEntity(name: 'COP', type: 'EVENT', theme: 'environment'),
      PopularEntity(name: 'Énergies renouvelables', type: 'TOPIC', theme: 'environment'),
      PopularEntity(name: 'Déforestation', type: 'TOPIC', theme: 'environment'),
    ],
    'international': [
      PopularEntity(name: 'OTAN', type: 'ORG', theme: 'international'),
      PopularEntity(name: 'ONU', type: 'ORG', theme: 'international'),
      PopularEntity(name: 'G7', type: 'EVENT', theme: 'international'),
      PopularEntity(name: 'BRICS', type: 'ORG', theme: 'international'),
    ],
  };

  /// Placeholders contextuels pour le CTA "Ajouter un sujet" par thème
  static const Map<String, String> customTopicPlaceholders = {
    'tech': 'ex: Anthropic, Bitcoin, React...',
    'international': 'ex: Dakar, Vendée Globe, OTAN...',
    'sport': 'ex: NBA, Rugby, Formule 1...',
    'culture': 'ex: Studio Ghibli, hip-hop, manga...',
    'science': 'ex: CERN, James Webb, archéologie...',
    'economy': 'ex: CAC 40, immobilier Paris...',
    'society': 'ex: réforme retraites, PMA...',
    'environment': 'ex: nucléaire, permaculture...',
    'politics': 'ex: RN, Renaissance, LFI...',
  };
}
