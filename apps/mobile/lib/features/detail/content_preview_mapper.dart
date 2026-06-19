import '../digest/models/digest_models.dart';
import '../feed/models/content_model.dart';
import '../flux_continu/models/flux_continu_models.dart';
import '../sources/models/source_model.dart';

/// Mappers « preview » : convertissent les modèles légers servis par
/// l'Essentiel / la Tournée / le Digest en un [Content] partiel passé en
/// `extra` à `ContentDetailScreen`. Cela permet d'afficher le header
/// (titre + image + source) instantanément au 1er frame, le corps montrant le
/// shimmer skeleton existant pendant que `getContent()` complète en arrière-plan
/// (même comportement « smooth loading » que Flâner).
///
/// Le merge réseau (`_fetchContent` + `copyWith` + `_pickLongest`) écrase/complète
/// proprement ce preview partiel dès l'arrivée des vraies données.
extension EssentielArticlePreview on EssentielArticle {
  /// Construit un [Content] partiel à partir d'une carte Essentiel.
  ///
  /// `description` (chapô) est servie par `/api/essentiel` → l'aperçu au
  /// long-press montre un corps dès le 1er frame ; le fetch complète ensuite.
  Content toPreviewContent() {
    return Content(
      id: contentId,
      title: title,
      url: url,
      thumbnailUrl: thumbnailUrl,
      description: description,
      contentType: ContentType.article,
      publishedAt: publishedAt,
      source: Source(
        id: '',
        name: sourceName,
        type: SourceType.article,
      ),
      isSaved: isSaved,
      isLiked: isLiked,
      isFollowedSource: isFollowedSource,
      status: isRead ? ContentStatus.consumed : ContentStatus.unseen,
    );
  }
}

extension DigestItemPreview on DigestItem {
  /// Construit un [Content] partiel à partir d'un item de digest.
  ///
  /// `DigestItem` est plus riche : il porte déjà `description`/`htmlContent`
  /// quand ils sont présents, donc le corps peut s'afficher directement sans
  /// passer par le shimmer.
  Content toPreviewContent() {
    final mini = source;
    return Content(
      id: contentId,
      title: title,
      url: url,
      thumbnailUrl: thumbnailUrl,
      description: description,
      htmlContent: htmlContent,
      contentType: contentType,
      durationSeconds: durationSeconds,
      publishedAt: publishedAt ?? DateTime.now(),
      source: Source(
        id: mini?.id ?? '',
        name: mini?.name ?? 'Inconnu',
        type: _sourceTypeFromString(mini?.type),
        theme: mini?.theme,
        logoUrl: mini?.logoUrl,
      ),
      topics: topics,
      isSaved: isSaved,
      isLiked: isLiked,
      isFollowedSource: isFollowedSource,
      isPaid: isPaid,
      status: isRead ? ContentStatus.consumed : ContentStatus.unseen,
      editorialBadge: badge,
    );
  }
}

SourceType _sourceTypeFromString(String? value) {
  return SourceType.values.firstWhere(
    (e) => e.name == value?.toLowerCase(),
    orElse: () => SourceType.article,
  );
}
