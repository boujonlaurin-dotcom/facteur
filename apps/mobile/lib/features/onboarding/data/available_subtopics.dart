class SubtopicOption {
  final String slug;
  final String label;
  final String emoji;

  const SubtopicOption({
    required this.slug,
    required this.label,
    required this.emoji,
  });
}

class AvailableSubtopics {
  static final Map<String, List<SubtopicOption>> byTheme = {
    'tech': [
      const SubtopicOption(
          slug: 'ai', label: 'Intelligence artificielle', emoji: '🤖'),
      const SubtopicOption(slug: 'gaming', label: 'Jeux vidéo', emoji: '🎮'),
      const SubtopicOption(
          slug: 'cybersecurity', label: 'Cybersécurité', emoji: '🔒'),
      const SubtopicOption(
          slug: 'privacy', label: 'Données et vie privée', emoji: '🛡️'),
    ],
    'society': [
      const SubtopicOption(
          slug: 'justice', label: 'Justice et droit', emoji: '⚖️'),
      const SubtopicOption(slug: 'health', label: 'Santé', emoji: '🩺'),
      const SubtopicOption(
          slug: 'education', label: 'Éducation', emoji: '🎓'),
      const SubtopicOption(
          slug: 'work', label: 'Emploi et travail', emoji: '💼'),
    ],
    'environment': [
      const SubtopicOption(slug: 'climate', label: 'Climat', emoji: '🌡️'),
      const SubtopicOption(
          slug: 'biodiversity', label: 'Biodiversité', emoji: '🐾'),
      const SubtopicOption(slug: 'energy', label: 'Énergie', emoji: '⚡'),
      const SubtopicOption(
          slug: 'agriculture', label: 'Agriculture', emoji: '🌾'),
    ],
    'economy': [
      const SubtopicOption(slug: 'finance', label: 'Finance', emoji: '💰'),
      const SubtopicOption(slug: 'startups', label: 'Startups', emoji: '🦄'),
      const SubtopicOption(
          slug: 'entrepreneurship', label: 'Entrepreneuriat', emoji: '💡'),
      const SubtopicOption(
          slug: 'realestate', label: 'Immobilier', emoji: '🏠'),
    ],
    'culture': [
      const SubtopicOption(slug: 'cinema', label: 'Cinéma', emoji: '🎬'),
      const SubtopicOption(
          slug: 'philosophy', label: 'Philosophie', emoji: '🤔'),
      const SubtopicOption(slug: 'history', label: 'Histoire', emoji: '📜'),
      const SubtopicOption(
          slug: 'gastronomy', label: 'Gastronomie', emoji: '🍽️'),
    ],
    'science': [
      const SubtopicOption(slug: 'science', label: 'Science', emoji: '🧪'),
      const SubtopicOption(
          slug: 'space', label: 'Espace et astronomie', emoji: '🚀'),
    ],
    'international': [
      const SubtopicOption(slug: 'europe', label: 'Europe', emoji: '🇪🇺'),
      const SubtopicOption(slug: 'usa', label: 'États-Unis', emoji: '🇺🇸'),
      const SubtopicOption(slug: 'asia', label: 'Asie', emoji: '🌏'),
      const SubtopicOption(
          slug: 'middleeast', label: 'Moyen-Orient', emoji: '🕌'),
    ],
    'sport': [
      const SubtopicOption(slug: 'sport', label: 'Sport', emoji: '⚽'),
    ],
  };
}
