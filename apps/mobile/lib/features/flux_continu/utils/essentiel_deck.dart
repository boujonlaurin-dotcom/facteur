import '../../detail/content_preview_mapper.dart';
import '../../detail/deck/models/article_deck.dart';
import '../../feed/models/content_model.dart' show FeedCarouselData;
import '../models/flux_continu_models.dart';
import '../providers/essentiel_triage_provider.dart';

/// Pool **ordonné** des articles adressables par la pile de tri du jour.
///
/// Slate du matin, puis les items du carrousel absents du slate, puis les
/// articles rapatriés au réseau (« Plus d'articles ? »). L'ordre est
/// significatif : le préfixe ne bouge jamais, donc rien de ce qui est déjà
/// affiché n'est rebattu — ni au tri, ni au cold-boot.
///
/// Source unique de cette composition : la carte l'utilise pour alimenter la
/// pile, [essentielArticleDeck] pour résoudre les gardés. Les deux doivent voir
/// exactement le même pool, sans quoi un gardé injecté via le carrousel
/// manquerait au deck.
List<EssentielArticle> essentielTriagePool({
  required List<EssentielArticle> articles,
  FeedCarouselData? carousel,
  List<EssentielArticle> fetched = const [],
}) {
  // Items du carrousel non déjà dans le slate, adaptés en articles triables.
  // Rangs au-delà du slate d'origine (le backend accepte leur tri avec le
  // `slate_size` **courant** que `decide()` envoie).
  final seen = {for (final a in articles) a.contentId};
  final extra = <EssentielArticle>[];
  final items = carousel?.items ?? const [];
  for (var i = 0; i < items.length; i++) {
    if (!seen.add(items[i].id)) continue; // déjà dans le slate
    extra.add(
      EssentielArticle.fromContent(items[i], rank: articles.length + i + 1),
    );
  }
  final fetchedFresh = [
    for (final a in fetched)
      if (seen.add(a.contentId)) a,
  ];
  return List.unmodifiable([...articles, ...extra, ...fetchedFresh]);
}

/// Deck de lecture de la carte « Ton Essentiel » (Story 34.1, ajustement v4).
///
/// L'Essentiel n'est plus un sommaire mais un **tri** : la navigation
/// inter-articles y suit donc l'état du tri, et non la liste servie par le
/// backend.
///
/// - **Lettre passée** (`isToday == false`) : figée, jamais triée. Le deck reste
///   la lettre entière — comportement d'origine de la 34.1.
/// - **Tri en cours** (ou pas encore déterminé) : `null`. Un tap sur la carte du
///   dessus ouvre l'article **seul** — la sélection n'est pas faite, il n'y a
///   pas encore de séquence de lecture à enchaîner, et le geste horizontal
///   appartient au tri.
/// - **Tri terminé** : le deck est **exactement** la liste des gardés, dans
///   l'ordre du slate — donc dans l'ordre où la carte les affiche sous « Tes
///   articles ». Les rejetés ne reviennent pas par le swipe, ce qui serait
///   annuler la décision qu'on vient de prendre.
///
/// Retourne `null` quand il n'y a rien à enchaîner : un seul gardé, ou un
/// article tapé hors de la liste des gardés (le reader s'ouvre alors nu).
ArticleDeckPayload? essentielArticleDeck({
  required EssentielSection section,
  required EssentielTriageState triage,
  required String tappedContentId,
  required bool isToday,
  List<EssentielArticle> fetched = const [],
}) {
  if (!isToday) return articleDeckFromSection(section, tappedContentId);
  // `done` couvre les deux cas où il n'y a pas (encore) de sélection : tri
  // actif, et tri indéterminé au cold-boot (`hasStarted` faux tant que le slate
  // n'est pas gelé — la carte rend alors sa silhouette, rien de tappable).
  if (!triage.done) return null;

  final pool = essentielTriagePool(
    articles: section.articles,
    carousel: section.carousel,
    fetched: fetched,
  );
  final byId = {for (final a in pool) a.contentId: a};
  final kept = [
    for (final id in triage.keptContentIds)
      if (byId[id] != null) byId[id]!.toPreviewContent(),
  ];

  return articleDeckFromContents(
    kept,
    tappedContentId,
    sectionKey: sectionKey(section),
    sectionLabel: section.label,
  );
}
