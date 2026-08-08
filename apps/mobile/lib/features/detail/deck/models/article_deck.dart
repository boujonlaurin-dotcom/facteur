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
    this.showPositionIndicator = true,
  });

  /// Articles de la section, dans l'ordre de lecture, dédupliqués par id.
  final List<Content> articles;

  /// Position de l'article sur lequel l'utilisateur a tapé.
  final int initialIndex;

  /// Clé stable de la section d'origine (`sectionKey()`), pour la mesure.
  final String sectionKey;

  /// Libellé lisible de la section — affiché dans l'affordance de retour.
  final String sectionLabel;

  /// Rend la barre de progression du header segmentée (1 segment par article).
  ///
  /// `false` sur les surfaces à liste **ouverte** (Flâner) : un « 3/8 » y
  /// mentirait, le feed n'a pas de fin connue. Le swipe y fonctionne quand même,
  /// simplement sans promettre un nombre d'articles restants.
  final bool showPositionIndicator;

  /// Un deck d'un seul article ne se navigue pas : la route rend alors le
  /// reader nu, sans `PageView` (zéro changement pour les appelants existants).
  bool get isNavigable => articles.length > 1;

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
    this.showSegments = false,
    this.webViewLock,
  });

  final int index;
  final int length;

  /// Page réellement au premier plan (page validée du `PageView`).
  final bool isActive;

  /// Barre de progression segmentée dans le header.
  final bool showSegments;

  /// Levé par le reader quand la WebView du site prend la main : le deck gèle
  /// alors le swipe horizontal, qui appartient à la page distante.
  final ValueNotifier<bool>? webViewLock;
}

/// Construit le deck d'une section de la Tournée autour de [tappedContentId].
///
/// Retourne `null` quand la section ne porte pas d'article navigable (section
/// d'alertes, article introuvable, section d'un seul article) — l'appelant
/// pousse alors simplement le `Content`.
ArticleDeckPayload? articleDeckFromSection(
  FluxSection section,
  String tappedContentId,
) {
  final items = switch (section) {
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

  return articleDeckFromContents(
    items,
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
  bool showPositionIndicator = true,
}) {
  if (tappedContentId.isEmpty) return null;

  final seen = <String>{};
  final deduped = <Content>[];
  for (final article in articles) {
    if (article.id.isEmpty) continue;
    if (!seen.add(article.id)) continue;
    deduped.add(article);
  }

  if (deduped.length < 2) return null;
  final index = deduped.indexWhere((a) => a.id == tappedContentId);
  if (index == -1) return null;

  return ArticleDeckPayload(
    articles: deduped,
    initialIndex: index,
    sectionKey: sectionKey,
    sectionLabel: sectionLabel,
    showPositionIndicator: showPositionIndicator,
  );
}
