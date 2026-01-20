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
      SubtopicOption(slug: 'ai', label: 'IA & Machine Learning', emoji: '🤖'),
      SubtopicOption(slug: 'crypto', label: 'Crypto & Web3', emoji: '⛓️'),
      SubtopicOption(slug: 'space', label: 'Spatial', emoji: '🚀'),
      SubtopicOption(
          slug: 'cybersecurity', label: 'Cybersécurité', emoji: '🔒'),
    ],
    'society': [
      SubtopicOption(
          slug: 'social-justice', label: 'Justice sociale', emoji: '⚖️'),
      SubtopicOption(slug: 'health', label: 'Santé', emoji: '🩺'),
      SubtopicOption(slug: 'education', label: 'Éducation', emoji: '🎓'),
      SubtopicOption(slug: 'housing', label: 'Logement', emoji: '🏠'),
    ],
    'environment': [
      SubtopicOption(slug: 'climate', label: 'Climat', emoji: '🌡️'),
      SubtopicOption(slug: 'biodiversity', label: 'Biodiversité', emoji: '🐾'),
      SubtopicOption(
          slug: 'energy-transition',
          label: 'Transition énergétique',
          emoji: '⚡'),
    ],
    'economy': [
      SubtopicOption(slug: 'macro', label: 'Économie', emoji: '📊'),
      SubtopicOption(slug: 'finance', label: 'Finance', emoji: '💰'),
      SubtopicOption(slug: 'startups', label: 'Startups', emoji: '🦄'),
    ],
    'politics': [
      SubtopicOption(slug: 'elections', label: 'Élections', emoji: '🗳️'),
      SubtopicOption(slug: 'institutions', label: 'Institutions', emoji: '🏛️'),
    ],
    'culture': [
      SubtopicOption(slug: 'philosophy', label: 'Philosophie', emoji: '🤔'),
      SubtopicOption(slug: 'cinema', label: 'Cinéma', emoji: '🎬'),
      SubtopicOption(
          slug: 'media-critics', label: 'Critique des médias', emoji: '📰'),
    ],
    'science': [
      SubtopicOption(
          slug: 'fundamental-research',
          label: 'Recherche fondamentale',
          emoji: '🧪'),
      SubtopicOption(
          slug: 'applied-science', label: 'Sciences appliquées', emoji: '⚙️'),
    ],
    'international': [
      SubtopicOption(slug: 'geopolitics', label: 'Géopolitique', emoji: '🌐'),
    ],
  };
}
