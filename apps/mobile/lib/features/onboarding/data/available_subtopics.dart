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
          slug: 'ai', label: 'IA & Machine Learning', emoji: '🤖'),
      const SubtopicOption(slug: 'gaming', label: 'Jeux vidéo', emoji: '🎮'),
      const SubtopicOption(
          slug: 'cybersecurity', label: 'Cybersécurité', emoji: '🔒'),
      const SubtopicOption(
          slug: 'privacy', label: 'Vie privée & données', emoji: '🛡️'),
    ],
    'society': [
      const SubtopicOption(
          slug: 'justice', label: 'Justice & droit', emoji: '⚖️'),
      const SubtopicOption(slug: 'health', label: 'Santé', emoji: '🩺'),
      const SubtopicOption(
          slug: 'education', label: 'Éducation', emoji: '🎓'),
      const SubtopicOption(
          slug: 'work', label: 'Emploi & travail', emoji: '💼'),
      const SubtopicOption(
          slug: 'immigration', label: 'Immigration', emoji: '🌍'),
    ],
    'environment': [
      const SubtopicOption(slug: 'climate', label: 'Climat', emoji: '🌡️'),
      const SubtopicOption(
          slug: 'biodiversity', label: 'Biodiversité', emoji: '🐾'),
      const SubtopicOption(slug: 'energy', label: 'Énergie', emoji: '⚡'),
    ],
    'economy': [
      const SubtopicOption(slug: 'economy', label: 'Économie', emoji: '📊'),
      const SubtopicOption(slug: 'finance', label: 'Finance', emoji: '💰'),
      const SubtopicOption(slug: 'startups', label: 'Startups', emoji: '🦄'),
    ],
    'politics': [
      const SubtopicOption(
          slug: 'politics', label: 'Politique', emoji: '🗳️'),
      // 'europe' is ML theme 'international', placed here for onboarding UX
      const SubtopicOption(slug: 'europe', label: 'Europe', emoji: '🇪🇺'),
    ],
    'culture': [
      const SubtopicOption(
          slug: 'philosophy', label: 'Philosophie', emoji: '🤔'),
      const SubtopicOption(slug: 'cinema', label: 'Cinéma', emoji: '🎬'),
      const SubtopicOption(slug: 'media', label: 'Médias', emoji: '📰'),
      const SubtopicOption(
          slug: 'gastronomy', label: 'Gastronomie', emoji: '🍽️'),
    ],
    'science': [
      const SubtopicOption(slug: 'science', label: 'Science', emoji: '🧪'),
      const SubtopicOption(slug: 'space', label: 'Espace', emoji: '🚀'),
    ],
    'international': [
      const SubtopicOption(
          slug: 'geopolitics', label: 'Géopolitique', emoji: '🌐'),
      const SubtopicOption(slug: 'usa', label: 'États-Unis', emoji: '🇺🇸'),
      const SubtopicOption(slug: 'africa', label: 'Afrique', emoji: '🌍'),
    ],
    'sport': [
      const SubtopicOption(slug: 'sport', label: 'Sport', emoji: '⚽'),
    ],
  };
}
