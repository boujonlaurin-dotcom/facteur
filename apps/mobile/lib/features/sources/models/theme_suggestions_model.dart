import 'source_model.dart';

/// Tier de contrôle éditorial d'une source poussée dans le footer
/// « Étoffer [thème] ». Miroir de `RecommendationTier` côté backend.
///
/// - [facteurPick] : pépite curée par l'équipe → branding fort
///   (« Recommandé par Facteur » + raison).
/// - [qualityCatalog] : source du catalogue évalué passant le gate qualité →
///   cadre neutre avec badge d'évaluation visible (biais + fiabilité).
///
/// Le Tier 3 (« Ta recherche ») n'est jamais renvoyé par l'endpoint : il
/// n'existe que via la recherche explicite de l'utilisateur.
enum ThemeSuggestionTier { facteurPick, qualityCatalog }

ThemeSuggestionTier _tierFromJson(String? raw) {
  switch (raw) {
    case 'facteur_pick':
      return ThemeSuggestionTier.facteurPick;
    case 'quality_catalog':
      return ThemeSuggestionTier.qualityCatalog;
    default:
      // Défaut prudent : cadre neutre plutôt que branding Facteur.
      return ThemeSuggestionTier.qualityCatalog;
  }
}

class ThemeSuggestion {
  final ThemeSuggestionTier tier;
  final Source source;

  const ThemeSuggestion({required this.tier, required this.source});

  factory ThemeSuggestion.fromJson(Map<String, dynamic> json) {
    return ThemeSuggestion(
      tier: _tierFromJson(json['recommendation_tier'] as String?),
      source: Source.fromJson(
        (json['source'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

/// Réponse du footer « Étoffer [thème] » — tiers POUSSÉS uniquement (1 & 2).
class ThemeSuggestions {
  final String theme;
  final String label;
  final List<ThemeSuggestion> suggestions;

  const ThemeSuggestions({
    required this.theme,
    required this.label,
    this.suggestions = const [],
  });

  factory ThemeSuggestions.fromJson(Map<String, dynamic> json) {
    final list = (json['suggestions'] as List?) ?? const [];
    return ThemeSuggestions(
      theme: (json['theme'] as String?) ?? '',
      label: (json['label'] as String?) ?? '',
      suggestions: list
          .whereType<Map<String, dynamic>>()
          .map(ThemeSuggestion.fromJson)
          .toList(growable: false),
    );
  }

  bool get isEmpty => suggestions.isEmpty;
}
