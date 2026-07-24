import '../../../config/topic_labels.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../sources/models/source_model.dart';
import '../models/search_result.dart';
import 'search_matcher.dart';

/// Un groupe de résultats affiché sous un intertitre dans la sheet.
class SearchSection {
  final String title;
  final List<SearchResult> results;

  /// Nombre de matches avant application du cap `perSectionLimit` — sert à
  /// afficher « voir tout (N) » sans recalculer.
  final int totalMatches;

  const SearchSection({
    required this.title,
    required this.results,
    required this.totalMatches,
  });

  bool get hasMore => totalMatches > results.length;
}

const String kSectionArticles = 'Articles';
const String kSectionSources = 'Tes sources';
const String kSectionTopics = 'Sujets suivis';
const String kSectionThemes = 'Thèmes';
const String kSectionAddSource = 'Ajouter une source';

/// True si la source compte comme « suivie » : ajoutée par l'utilisateur
/// (catalogue trusté ou flux custom) et non mise en sourdine.
bool isFollowedSource(Source s) => (s.isTrusted || s.isCustom) && !s.isMuted;

/// Construit les sections de résultats pour [query], **entièrement en local**.
///
/// [allSources] est la liste complète renvoyée par `userSourcesProvider`
/// (catalogue curé + sources custom, avec les drapeaux `isTrusted` / `isMuted`),
/// ce qui permet de distinguer sans appel réseau :
/// - une source déjà suivie → on propose de filtrer dessus ;
/// - une source du catalogue pas encore ajoutée → on propose de l'ajouter ;
/// - une source inconnue → on bascule sur la recherche intelligente.
///
/// L'ordre des sections s'adapte à l'intention : taper « Mediapart » ou
/// « lemonde.fr » remonte les sources devant la recherche par mot-clé, parce
/// qu'un nom de média n'a aucun sens comme filtre sur les titres d'articles.
List<SearchSection> buildSearchSections({
  required String query,
  required List<Source> allSources,
  required List<UserTopicProfile> topics,
  int perSectionLimit = 3,
}) {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return const [];

  final followedMatches = rankMatches<Source>(
    trimmed,
    allSources.where(isFollowedSource),
    label: (s) => s.name,
    aliases: (s) => [if (s.url != null) s.url!],
  );

  // Sources du catalogue jamais ajoutées. Les sources en sourdine sont
  // volontairement exclues : les re-proposer à l'ajout contredirait un choix
  // explicite de l'utilisateur (le rétablissement passe par les réglages).
  final catalogMatches = rankMatches<Source>(
    trimmed,
    allSources.where((s) => !s.isTrusted && !s.isCustom && !s.isMuted),
    label: (s) => s.name,
    aliases: (s) => [if (s.url != null) s.url!],
  );

  final topicMatches = rankMatches<UserTopicProfile>(
    trimmed,
    topics,
    label: (t) => t.name,
    aliases: (t) => [if (t.canonicalName != null) t.canonicalName!],
  );

  final themeMatches = rankMatches<String>(
    trimmed,
    macroThemeOrder,
    label: (t) => t,
  );

  bool hasExact(List<RankedMatch<Source>> m) =>
      m.isNotEmpty && m.first.quality == MatchQuality.exact;
  final sourceIntent = looksLikeSourceQuery(trimmed) ||
      hasExact(followedMatches) ||
      hasExact(catalogMatches);

  SearchSection? section(String title, List<SearchResult> all) {
    if (all.isEmpty) return null;
    return SearchSection(
      title: title,
      results:
          all.length > perSectionLimit ? all.sublist(0, perSectionLimit) : all,
      totalMatches: all.length,
    );
  }

  final articles = SearchSection(
    title: kSectionArticles,
    results: [KeywordResult(trimmed)],
    totalMatches: 1,
  );

  final sources = section(
    kSectionSources,
    followedMatches.map<SearchResult>((m) => FollowedSourceResult(m.item)).toList(),
  );

  final subjects = section(
    kSectionTopics,
    topicMatches.map<SearchResult>((m) => TopicResult(m.item)).toList(),
  );

  final themes = section(
    kSectionThemes,
    themeMatches
        .map<SearchResult>(
          (m) => ThemeResult(
            label: m.item,
            slug: macroThemeToApiSlug[m.item] ?? m.item,
            emoji: getMacroThemeEmoji(m.item),
          ),
        )
        .toList(),
  );

  // La section « Ajouter » est toujours présente : même sans match catalogue,
  // la recherche intelligente reste la porte de sortie d'une requête bredouille.
  final addResults = <SearchResult>[
    ...catalogMatches
        .take(perSectionLimit - 1)
        .map((m) => CatalogSourceResult(m.item)),
    AddSourceResult(trimmed),
  ];
  final addSource = SearchSection(
    title: kSectionAddSource,
    results: addResults,
    totalMatches: catalogMatches.length + 1,
  );

  final ordered = sourceIntent
      ? [sources, addSource, subjects, themes, articles]
      : [articles, sources, subjects, themes, addSource];

  return ordered.whereType<SearchSection>().toList();
}
