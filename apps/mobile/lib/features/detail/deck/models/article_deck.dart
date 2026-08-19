import 'package:flutter/foundation.dart';

import '../../../feed/models/content_model.dart';
import '../../../flux_continu/models/flux_continu_models.dart';
import '../../content_preview_mapper.dart';

/// Séquence d'articles navigable au swipe depuis le reader (Story 34.1).
///
/// Le deck porte la **liste complète** de la section d'origine, pas l'aperçu
/// rendu sur la Tournée : une section n'affiche souvent que 2 cartes
/// (`coreVisibleCount`) alors que `FeedThemeSection.items` en porte 5-8. Glisser
/// depuis le 2ᵉ article affiché mène donc au 3ᵉ **disponible**, celui qu'il
/// fallait jusqu'ici aller chercher derrière « Tout lire ».
///
/// Passé en `extra` à la route `content/:id`. Quand l'`extra` est perdu (deep
/// link, notification, restauration OS), la route retombe sur un `Content` seul
/// et le reader s'ouvre sans deck — comportement historique.
@immutable
class ArticleDeckPayload {
  const ArticleDeckPayload({
    required this.articles,
    required this.initialIndex,
    required this.sectionKey,
    required this.sectionLabel,
    this.nextSectionDeck,
    this.onArticleSettled,
    this.onSectionAdvanced,
  });

  /// Articles de la section, dans l'ordre de lecture, dédupliqués par id.
  final List<Content> articles;

  /// Position de l'article sur lequel l'utilisateur a tapé.
  final int initialIndex;

  /// Clé stable de la section d'origine (`sectionKey()`), pour la mesure.
  final String sectionKey;

  /// Libellé lisible de la section — affiché dans l'affordance de retour.
  final String sectionLabel;

  /// Deck de la **section suivante** de la Tournée, résolu à la demande
  /// (Story 34.2), ou `null` quand il n'y a pas de suite.
  ///
  /// Paresseux et récursif : le deck rendu porte lui-même son propre
  /// `nextSectionDeck`, de sorte que la tournée entière s'enchaîne sans jamais
  /// construire d'avance plus d'une section. `null` partout où la liste est
  /// ouverte ou hors tournée (Flâner, pages section dédiées).
  final ArticleDeckPayload? Function()? nextSectionDeck;

  /// Notifie la surface d'origine de l'article **validé** courant, à chaque
  /// changement de page.
  ///
  /// C'est le fil qui permet à un feed de se rouvrir là où la lecture s'est
  /// arrêtée : sortir du deck après avoir enchaîné 4 articles doit ramener sur
  /// le 4ᵉ, pas sur celui qu'on avait tapé. Il passe par le payload plutôt que
  /// par le résultat du `pop` parce que le deck se referme par quatre chemins
  /// (flèche du header, geste de bord, back système, tirage en tête de deck) et
  /// qu'un seul d'entre eux porte une valeur de retour.
  ///
  /// `null` quand l'appelant n'a rien à repositionner. Non transporté par un
  /// deep link : l'`extra` perdu, le deck l'est aussi.
  final void Function(Content article)? onArticleSettled;

  /// Notifie la surface d'origine du passage à la section suivante.
  ///
  /// Même rôle que [onArticleSettled], d'un cran au-dessus : quitter le deck
  /// après avoir déroulé cinq sections doit ramener sur la Tournée **à la
  /// cinquième**, pas à celle d'où l'on était parti. La chaîne entière porte la
  /// même fonction (cf. `tourneeArticleDeck`), donc l'appelant reçoit chaque
  /// étape, quelle que soit sa profondeur.
  final void Function(ArticleDeckPayload next)? onSectionAdvanced;

  /// Un deck d'un seul article **sans suite** ne se navigue pas : la route rend
  /// alors le reader nu, sans `PageView` (zéro changement pour les appelants
  /// existants). Avec une section suivante, il reste un deck : c'est elle qui
  /// porte la navigation.
  bool get isNavigable => articles.length > 1 || nextSectionDeck != null;

  Content get initialArticle => articles[initialIndex];
}

/// Place d'une page dans le deck, passée au reader.
///
/// [isActive] est le levier central : une page seulement *entrevue* pendant le
/// drag ne doit ni se marquer « Lu », ni compter une ouverture, ni armer ses
/// nudges (cf. `ContentDetailScreen._activateDeckPage`).
@immutable
class ArticleDeckSlot {
  const ArticleDeckSlot({
    required this.index,
    required this.length,
    required this.isActive,
    this.webViewLock,
  });

  final int index;
  final int length;

  /// Page réellement au premier plan (page validée du `PageView`).
  final bool isActive;

  /// Levé par le reader quand la WebView du site prend la main : le deck gèle
  /// alors le swipe horizontal, qui appartient à la page distante.
  final ValueNotifier<bool>? webViewLock;
}

/// Articles réellement enchaînables d'une section, dans l'ordre de lecture.
///
/// C'est la liste **complète** de la section, pas son aperçu (`coreVisibleCount`).
List<Content> sectionArticles(FluxSection section) => switch (section) {
      EssentielSection(articles: final list) =>
        list.map((a) => a.toPreviewContent()).toList(growable: false),
      DigestTopicSection(topics: final list) => list
          .where((t) => t.articles.isNotEmpty)
          .map((t) => pickTopicLead(t).toPreviewContent())
          .toList(growable: false),
      FeedThemeSection(items: final list) => list,
      CarouselSection(data: final data) => data.items,
      // Le rappel d'alertes ne rend aucun article : rien à enchaîner.
      AlertsSection() => const <Content>[],
    };

/// Construit le deck d'une section de la Tournée autour de [tappedContentId].
///
/// Retourne `null` quand la section ne porte pas d'article navigable (section
/// d'alertes, article introuvable, section d'un seul article) — l'appelant
/// pousse alors simplement le `Content`.
ArticleDeckPayload? articleDeckFromSection(
  FluxSection section,
  String tappedContentId,
) {
  return articleDeckFromContents(
    sectionArticles(section),
    tappedContentId,
    sectionKey: sectionKey(section),
    sectionLabel: section.label,
  );
}

/// Construit un deck depuis une liste d'articles déjà résolue (Flâner,
/// carrousels, blocs Explorer). Dédup par id et positionnement sur
/// [tappedContentId].
ArticleDeckPayload? articleDeckFromContents(
  List<Content> articles,
  String tappedContentId, {
  required String sectionKey,
  required String sectionLabel,
  void Function(Content article)? onArticleSettled,
}) {
  if (tappedContentId.isEmpty) return null;

  final deduped = _dedupById(articles);
  if (deduped.length < 2) return null;
  final index = deduped.indexWhere((a) => a.id == tappedContentId);
  if (index == -1) return null;

  return ArticleDeckPayload(
    articles: deduped,
    initialIndex: index,
    sectionKey: sectionKey,
    sectionLabel: sectionLabel,
    onArticleSettled: onArticleSettled,
  );
}

/// Deck d'une section de la Tournée **chaîné aux sections suivantes**
/// (Story 34.2) : arrivé au bout de sa section, le deck sait proposer la
/// suivante, et ainsi de suite jusqu'à la fin de la tournée.
///
/// [sections] est le snapshot **ordonné** rendu à l'écran ; le chaînage suit cet
/// ordre exact. Le deck de la section suivante n'est construit qu'au moment où
/// on l'atteint (fonction paresseuse), donc lire un seul article ne coûte jamais
/// la mise à plat de toute la tournée.
///
/// Retombe sur [articleDeckFromSection] si la section n'appartient pas au
/// snapshot (vue lettre, agrégat hebdo) : il n'y a alors pas d'ordre de tournée
/// où chercher une suite.
ArticleDeckPayload? tourneeArticleDeck(
  List<FluxSection> sections,
  FluxSection section,
  String tappedContentId, {
  void Function(ArticleDeckPayload next)? onSectionAdvanced,
}) {
  if (tappedContentId.isEmpty) return null;
  var index = sections.indexWhere((s) => identical(s, section));
  if (index == -1) {
    final key = sectionKey(section);
    index = sections.indexWhere((s) => sectionKey(s) == key);
  }
  if (index == -1) return articleDeckFromSection(section, tappedContentId);
  return _tourneeDeckAt(
    sections,
    index,
    tappedContentId,
    onSectionAdvanced: onSectionAdvanced,
  );
}

/// Deck de la section d'index [index], positionné sur [tappedContentId] (vide =
/// premier article de la section, cas d'une section atteinte par enchaînement).
ArticleDeckPayload? _tourneeDeckAt(
  List<FluxSection> sections,
  int index,
  String tappedContentId, {
  void Function(ArticleDeckPayload next)? onSectionAdvanced,
}) {
  final section = sections[index];
  final articles = _dedupById(sectionArticles(section));
  if (articles.isEmpty) return null;

  final start = tappedContentId.isEmpty
      ? 0
      : articles.indexWhere((a) => a.id == tappedContentId);
  if (start == -1) return null;

  final nextIndex = _nextArticleSectionIndex(sections, index);
  // Ni voisin, ni suite : ce n'est pas un deck, la route rendra le reader nu.
  if (articles.length < 2 && nextIndex == null) return null;

  return ArticleDeckPayload(
    articles: articles,
    initialIndex: start,
    sectionKey: sectionKey(section),
    sectionLabel: section.label,
    nextSectionDeck: nextIndex == null
        ? null
        // La chaîne transporte la même notification d'étape jusqu'au bout : la
        // Tournée sait donc toujours à quelle section la lecture s'est arrêtée.
        : () => _tourneeDeckAt(
              sections,
              nextIndex,
              '',
              onSectionAdvanced: onSectionAdvanced,
            ),
    onSectionAdvanced: onSectionAdvanced,
  );
}

/// Index de la première section **après** [from] qui rend au moins un article.
///
/// Les sections sans article (rappel d'alertes, bloc vide) sont sautées : elles
/// ne peuvent pas être une étape de lecture.
int? _nextArticleSectionIndex(List<FluxSection> sections, int from) {
  for (var i = from + 1; i < sections.length; i++) {
    if (sectionArticles(sections[i]).any((a) => a.id.isNotEmpty)) return i;
  }
  return null;
}

List<Content> _dedupById(List<Content> articles) {
  final seen = <String>{};
  final deduped = <Content>[];
  for (final article in articles) {
    if (article.id.isEmpty) continue;
    if (!seen.add(article.id)) continue;
    deduped.add(article);
  }
  return deduped;
}
