import '../../custom_topics/models/topic_models.dart';
import '../../sources/models/source_model.dart';

/// Les cinq natures de résultat que la recherche universelle (story 30.1) sait
/// produire. Chacune correspond à un geste déjà supporté par `FeedNotifier`
/// (`setKeyword` / `setSource` / `setTopic` / `setEntity` / `setTheme`), sauf
/// [AddSourceResult] qui bifurque vers le flow d'ajout de source.
sealed class SearchResult {
  const SearchResult();

  /// Identifiant analytics de la nature du résultat (`search_result_selected`).
  String get analyticsType;
}

/// « Rechercher « q » dans les articles » — comportement historique de la loupe.
class KeywordResult extends SearchResult {
  final String query;

  const KeywordResult(this.query);

  @override
  String get analyticsType => 'article';
}

/// Une source **déjà suivie** : tap = filtre le flux dessus.
class FollowedSourceResult extends SearchResult {
  final Source source;

  const FollowedSourceResult(this.source);

  @override
  String get analyticsType => 'source';
}

/// Une source du catalogue **pas encore suivie** : tap = `trustSource` puis
/// filtre. La sheet ne se ferme qu'une fois l'ajout confirmé.
class CatalogSourceResult extends SearchResult {
  final Source source;

  const CatalogSourceResult(this.source);

  @override
  String get analyticsType => 'catalog_source';
}

/// Un sujet suivi (custom topic ou entité) : tap = `setTopic` / `setEntity`.
class TopicResult extends SearchResult {
  final UserTopicProfile topic;

  const TopicResult(this.topic);

  /// Les entités (personne, organisation, lieu…) se filtrent par nom canonique,
  /// les sujets classiques par slug parent — même dispatch que
  /// `InterestFilterSheet`.
  bool get isEntity => topic.entityType != null;

  String get filterValue =>
      isEntity ? (topic.canonicalName ?? topic.name) : (topic.slugParent ?? topic.id);

  @override
  String get analyticsType => isEntity ? 'entity' : 'topic';
}

/// Un des 9 macro-thèmes : tap = `setTheme(slug)`.
class ThemeResult extends SearchResult {
  final String label;
  final String slug;
  final String emoji;

  const ThemeResult({
    required this.label,
    required this.slug,
    required this.emoji,
  });

  @override
  String get analyticsType => 'theme';
}

/// « Chercher « q » sur le web et l'ajouter » — pont vers `AddSourceScreen`
/// avec la recherche intelligente pré-remplie.
class AddSourceResult extends SearchResult {
  final String query;

  const AddSourceResult(this.query);

  @override
  String get analyticsType => 'add_source';
}
