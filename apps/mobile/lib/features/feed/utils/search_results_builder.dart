import '../../../config/topic_labels.dart';
import '../../custom_topics/models/topic_models.dart';
import '../../sources/models/source_model.dart';
import '../models/search_result.dart';
import 'search_matcher.dart';

/// Un groupe de résultats affiché sous un intertitre dans la sheet.
class SearchSection {
  final String title;

  /// Vue cappée à `perSectionLimit` — ce qu'on affiche par défaut.
  final List<SearchResult> results;

  /// Tous les matches, sans cap : le « voir tout » de la sheet déplie la
  /// section sans relancer le calcul.
  final List<SearchResult> allResults;

  const SearchSection({
    required this.title,
    required this.results,
    required this.allResults,
  });

  int get totalMatches => allResults.length;

  bool get hasMore => allResults.length > results.length;
}

const String kSectionArticles = 'Articles';
const String kSectionSources = 'Tes sources';
const String kSectionTopics = 'Sujets suivis';
const String kSectionThemes = 'Thèmes';
const String kSectionAddSource = 'Chercher une source';

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

  // Un match exact ne remonte pas forcément en tête du classement (un préfixe
  // plus court peut passer devant) — on balaie donc toute la liste.
  bool hasExact(List<RankedMatch<Source>> m) =>
      m.any((match) => match.quality == MatchQuality.exact);
  final sourceIntent = looksLikeSourceQuery(trimmed) ||
      hasExact(followedMatches) ||
      hasExact(catalogMatches);

  SearchSection? section(String title, List<SearchResult> all) {
    if (all.isEmpty) return null;
    return SearchSection(
      title: title,
      results:
          all.length > perSectionLimit ? all.sublist(0, perSectionLimit) : all,
      allResults: all,
    );
  }

  final articles = SearchSection(
    title: kSectionArticles,
    results: [KeywordResult(trimmed)],
    allResults: [KeywordResult(trimmed)],
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
    themeMatches.map<SearchResult>((m) => _themeResultFor(m.item)).toList(),
  );

  // La section « Ajouter » est toujours présente, et la recherche intelligente
  // toujours en dernière ligne — cappée comme dépliée : c'est la porte de
  // sortie d'une requête bredouille, elle ne doit jamais être tronquée.
  final addSource = SearchSection(
    title: kSectionAddSource,
    results: <SearchResult>[
      ...catalogMatches
          .take(perSectionLimit - 1)
          .map((m) => CatalogSourceResult(m.item)),
      AddSourceResult(trimmed),
    ],
    allResults: <SearchResult>[
      ...catalogMatches.map((m) => CatalogSourceResult(m.item)),
      AddSourceResult(trimmed),
    ],
  );

  final ordered = sourceIntent
      ? [sources, addSource, subjects, themes, articles]
      : [articles, sources, subjects, themes, addSource];

  return ordered.whereType<SearchSection>().toList();
}

/// Match **exact** de [query] sur une source suivie, un sujet/entité suivi ou
/// un thème — dans cet ordre de priorité.
///
/// Sert à rediriger une recherche tapée au clavier (ou une chip d'historique)
/// vers le filtre de catalogue correspondant plutôt que vers un mot-clé
/// générique, quand `q` correspond exactement au nom d'un onglet déjà épinglé
/// (`FavoriteTopicTabs` sait alors le scroller en vue automatiquement).
SearchResult? findExactFollowedMatch({
  required String query,
  required List<Source> allSources,
  required List<UserTopicProfile> topics,
}) {
  final foldedQuery = foldForSearch(query.trim());
  if (foldedQuery.isEmpty) return null;

  // Seule l'égalité exacte compte : replier le libellé et comparer suffit —
  // inutile de payer les tiers préfixe/mot/fuzzy de `qualityOfFolded`.
  bool isExact(String label) => foldForSearch(label.trim()) == foldedQuery;

  for (final s in allSources.where(isFollowedSource)) {
    if (isExact(s.name) || (s.url != null && isExact(s.url!))) {
      return FollowedSourceResult(s);
    }
  }

  for (final t in topics) {
    if (isExact(t.name) || (t.canonicalName != null && isExact(t.canonicalName!))) {
      return TopicResult(t);
    }
  }

  for (final theme in macroThemeOrder) {
    if (isExact(theme)) return _themeResultFor(theme);
  }

  return null;
}

/// Construit le [ThemeResult] d'un thème macro (slug API + emoji) — partagé par
/// `buildSearchSections` et `findExactFollowedMatch` pour que les deux chemins
/// ne dérivent jamais sur la dérivation slug/emoji.
ThemeResult _themeResultFor(String theme) => ThemeResult(
      label: theme,
      slug: macroThemeToApiSlug[theme] ?? theme,
      emoji: getMacroThemeEmoji(theme),
    );
