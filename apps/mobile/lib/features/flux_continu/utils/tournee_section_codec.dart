import 'dart:ui' show Color;

import '../../feed/models/content_model.dart';
import '../models/flux_continu_models.dart';

/// Codec de l'**en-tête** d'une section Tournée persistée (SWR in-day).
///
/// Pourquoi un en-tête séparé plutôt que de rejouer les builders du provider à
/// l'hydratation : au boot, `userSourcesProvider` et `veilleActiveConfigProvider`
/// ne sont pas résolus (lecture `_peekValue`, qui n'initialise volontairement
/// aucun provider depuis le lot « héros d'abord ») — `_shellSourceSections` et
/// `_buildVeilleSection` droppent alors la section. En persistant l'en-tête de
/// la section **réellement rendue**, la réouverture in-day la reconstruit à
/// l'identique sans dépendre d'un provider réseau.
///
/// Ne sont **pas** persistés les champs dérivés à chaque `_compose`
/// (`underfilled`, `isPlaceholder`), l'état de pagination en vol
/// (`currentPage`, `isLoadingMore`) ni `origin`/`reason` : les sections
/// « Choisie pour vous » ne sont jamais mises en cache (leur retrait `onEmpty`
/// les ferait disparaître sous le doigt).
Map<String, dynamic> encodeTourneeSectionHeader(FeedThemeSection section) {
  return <String, dynamic>{
    'kind': section.kind.name,
    'label': section.label,
    'blurb': section.blurb,
    'accent': section.accent.toARGB32(),
    'illustration_asset': section.illustrationAsset,
    'core_visible_count': section.coreVisibleCount,
    'theme_slug': section.themeSlug,
    'custom_topic_id': section.customTopicId,
    'source_id': section.sourceId,
    'source_logo_url': section.sourceLogoUrl,
    'has_more': section.hasMore,
    'no_recent_source': section.noRecentSource,
    'followed_source_count': section.followedSourceCount,
  };
}

/// Reconstruit une section depuis son en-tête persisté et ses [items] relus.
/// Renvoie `null` sur un en-tête incomplet ou d'un `kind` hors Tournée
/// (fail-closed : mieux vaut une coquille que la mauvaise section).
FeedThemeSection? decodeTourneeSection(
  Map<String, dynamic> header,
  List<Content> items,
) {
  final kindName = header['kind'];
  final label = header['label'];
  final accent = header['accent'];
  final coreVisibleCount = header['core_visible_count'];
  if (kindName is! String ||
      label is! String ||
      accent is! int ||
      coreVisibleCount is! int) {
    return null;
  }
  final kind = switch (kindName) {
    'theme' => SectionKind.theme,
    'source' => SectionKind.source,
    'veille' => SectionKind.veille,
    _ => null,
  };
  if (kind == null) return null;
  return FeedThemeSection(
    kind: kind,
    label: label,
    blurb: header['blurb'] as String?,
    accent: Color(accent),
    illustrationAsset: header['illustration_asset'] as String?,
    coreVisibleCount: coreVisibleCount,
    themeSlug: header['theme_slug'] as String?,
    customTopicId: header['custom_topic_id'] as String?,
    sourceId: header['source_id'] as String?,
    sourceLogoUrl: header['source_logo_url'] as String?,
    items: items,
    hasMore: header['has_more'] as bool? ?? false,
    noRecentSource: header['no_recent_source'] as bool? ?? false,
    followedSourceCount: header['followed_source_count'] as int? ?? 0,
  );
}
