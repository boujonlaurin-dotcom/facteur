import '../../../config/routes.dart';
import '../models/letter.dart';

/// Normalise les routes de progression vers les surfaces actuelles de l'app.
///
/// Défense en profondeur :
/// - mappe les actions connues vers leurs destinations canoniques ;
/// - remappe les anciennes routes serveur encore possibles (`/feed`, `/digest`)
///   pour éviter les push vers des écrans legacy.
String? resolveLetterActionRoute(LetterAction action) {
  switch (action.id) {
    case 'define_editorial_line':
      return RoutePaths.myInterests;
    case 'add_5_sources':
      return RoutePaths.sources;
    case 'add_2_personal_sources':
      return '${RoutePaths.sources}/add';
    case 'first_perspectives_open':
    case 'read_3_long_articles':
    case 'read_first_video_podcast':
    case 'recommend_first_article':
    case 'save_5_articles':
    case 'mute_3_sources':
    case 'read_50_articles':
    case 'recommend_10_articles':
    case 'open_10_perspectives':
      return RoutePaths.flaner;
    case 'read_first_essentiel':
      return '${RoutePaths.fluxContinu}/section/essentiel';
    case 'read_first_bonnes_nouvelles':
      return '${RoutePaths.fluxContinu}/section/bonnes';
    case 'create_first_veille':
      return RoutePaths.veilleConfig;
    case 'write_first_note':
      return RoutePaths.saved;
    case 'add_5_youtube_channels':
      return '${RoutePaths.sources}/add';
    case 'give_app_feedback':
      return RoutePaths.settings;
  }

  final raw = action.targetRoute?.trim();
  if (raw == null || raw.isEmpty) return null;

  final uri = Uri.tryParse(raw);
  if (uri == null) return raw;

  switch (uri.path) {
    case RoutePaths.feed:
      return RoutePaths.flaner;
    case RoutePaths.digest:
      return uri.queryParameters['serein'] == '1'
          ? '${RoutePaths.fluxContinu}/section/bonnes'
          : '${RoutePaths.fluxContinu}/section/essentiel';
    case RoutePaths.myInterests:
    case RoutePaths.sources:
      return uri.path;
  }

  if (uri.path == '${RoutePaths.sources}/add') {
    return uri.path;
  }

  return raw;
}
