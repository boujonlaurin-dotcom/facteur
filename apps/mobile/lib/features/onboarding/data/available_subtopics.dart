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
      const SubtopicOption(slug: 'crypto', label: 'Crypto & Web3', emoji: '⛓️'),
      const SubtopicOption(slug: 'space', label: 'Spatial', emoji: '🚀'),
      const SubtopicOption(
          slug: 'cybersecurity', label: 'Cybersécurité', emoji: '🔒'),
    ],
    'society': [
      const SubtopicOption(
          slug: 'social-justice', label: 'Justice sociale', emoji: '⚖️'),
      const SubtopicOption(slug: 'health', label: 'Santé', emoji: '🩺'),
      const SubtopicOption(slug: 'education', label: 'Éducation', emoji: '🎓'),
      const SubtopicOption(slug: 'housing', label: 'Logement', emoji: '🏠'),
    ],
    'environment': [
      const SubtopicOption(slug: 'climate', label: 'Climat', emoji: '🌡️'),
      const SubtopicOption(
          slug: 'biodiversity', label: 'Biodiversité', emoji: '🐾'),
      const SubtopicOption(
          slug: 'energy-transition',
          label: 'Transition énergétique',
          emoji: '⚡'),
    ],
    'economy': [
      const SubtopicOption(slug: 'macro', label: 'Économie', emoji: '📊'),
      const SubtopicOption(slug: 'finance', label: 'Finance', emoji: '💰'),
      const SubtopicOption(slug: 'startups', label: 'Startups', emoji: '🦄'),
    ],
    'politics': [
      const SubtopicOption(slug: 'elections', label: 'Élections', emoji: '🗳️'),
      const SubtopicOption(
          slug: 'institutions', label: 'Institutions', emoji: '🏛️'),
    ],
    'culture': [
      const SubtopicOption(
          slug: 'philosophy', label: 'Philosophie', emoji: '🤔'),
      const SubtopicOption(slug: 'cinema', label: 'Cinéma', emoji: '🎬'),
      const SubtopicOption(
          slug: 'media-critics', label: 'Critique des médias', emoji: '📰'),
    ],
    'science': [
      const SubtopicOption(
          slug: 'fundamental-research',
          label: 'Recherche fondamentale',
          emoji: '🧪'),
      const SubtopicOption(
          slug: 'applied-science', label: 'Sciences appliquées', emoji: '⚙️'),
    ],
    'international': [
      const SubtopicOption(
          slug: 'geopolitics', label: 'Géopolitique', emoji: '🌐'),
    ],
  };
}
