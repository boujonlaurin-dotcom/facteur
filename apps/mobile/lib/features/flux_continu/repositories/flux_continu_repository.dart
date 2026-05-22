import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/providers.dart';
import '../../feed/models/content_model.dart';

/// One entry of `GET /api/users/top-themes`.
///
/// Slug values are constrained to the 9 valid Facteur theme slugs (cf.
/// `packages/api/app/services/ml/topic_theme_mapper.py` VALID_THEMES). Weight
/// is the user-learned interest weight; `articleCount` is the number of
/// articles published in the last 14 days carrying that theme.
class TopTheme {
  final String interestSlug;
  final double weight;
  final int articleCount;

  const TopTheme({
    required this.interestSlug,
    required this.weight,
    this.articleCount = 0,
  });

  factory TopTheme.fromJson(Map<String, dynamic> json) {
    return TopTheme(
      interestSlug: (json['interest_slug'] as String?) ?? '',
      weight: (json['weight'] as num?)?.toDouble() ?? 0.0,
      articleCount: (json['article_count'] as num?)?.toInt() ?? 0,
    );
  }
}

/// Repository scoped to the Flux Continu V1.8 feature.
///
/// Owns calls that aren't covered by existing per-feature repositories:
/// - `GET /api/users/top-themes` → ranked user interests for sections #3/#4.
///
/// Digest payloads use [DigestRepository.fetchBothDigests], and themed feed
/// payloads use [FeedRepository.getFeed] with `theme: ...`. We don't proxy
/// those here — the provider composes the three directly.
class FluxContinuRepository {
  final ApiClient _apiClient;

  FluxContinuRepository(this._apiClient);

  Future<List<TopTheme>> getTopThemes() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('users/top-themes');
      if (response.statusCode == 200 && response.data is List) {
        return (response.data as List)
            .whereType<Map<String, dynamic>>()
            .map(TopTheme.fromJson)
            .toList();
      }
      return const [];
    } on DioException catch (e) {
      // Top-themes is non-critical: a 404/500 should not block the screen.
      // The provider falls back to fixed slugs (tech + environment) when
      // the list is empty, so we surface an empty list here too.
      // ignore: avoid_print
      print('FluxContinuRepository: getTopThemes failed: ${e.message}');
      return const [];
    }
  }

  /// `GET /api/veille/feed` — Story 23.2 PR-4. Renvoie les articles matchant
  /// la veille active de l'utilisateur. Le backend (`fetch_veille_feed`)
  /// applique le filtre OR (thèmes/topics/sources/keywords) + boost
  /// `VeilleMatchLayer` sur le feed Facteur principal.
  ///
  /// On normalise la réponse `VeilleFeedResponse` en `FeedResponse` standard
  /// pour pouvoir réutiliser le même rendu UI que les autres sections Tournée
  /// (cf. `_buildThemeSection`). Les champs spécifiques veille (matched_on)
  /// sont droppés ici — la section veille a son propre branding (accent
  /// sectionVeille1 + badge "Ma veille") qui rend matched_on superflu V1.
  Future<FeedResponse> getVeilleFeedItems({
    int limit = 10,
    bool serein = false,
  }) async {
    try {
      final response = await _apiClient.dio.get<dynamic>(
        'veille/feed',
        queryParameters: {'limit': limit, 'offset': 0, 'serein': serein},
      );
      if (response.statusCode != 200 || response.data is! Map) {
        return FeedResponse(
          items: const [],
          pagination: Pagination(page: 1, perPage: limit, total: 0, hasNext: false),
        );
      }
      final data = response.data as Map<String, dynamic>;
      final rawItems = (data['items'] as List?) ?? const [];
      final items = rawItems
          .whereType<Map<String, dynamic>>()
          .map(_veilleArticleToContentJson)
          .map(Content.fromJson)
          .toList();
      return FeedResponse(
        items: items,
        pagination: Pagination(
          page: 1,
          perPage: limit,
          total: (data['total'] as num?)?.toInt() ?? items.length,
          hasNext: (data['has_more'] as bool?) ?? false,
        ),
      );
    } on DioException catch (e) {
      // ignore: avoid_print
      print('FluxContinuRepository: getVeilleFeedItems failed: ${e.message}');
      return FeedResponse(
        items: const [],
        pagination: Pagination(page: 1, perPage: limit, total: 0, hasNext: false),
      );
    }
  }

  /// Normalise un `VeilleFeedArticle` (schéma backend `schemas/veille.py`)
  /// en JSON Content-compatible. Les fields manquants (content_type, status,
  /// is_saved, etc.) reçoivent leurs valeurs par défaut via `Content.fromJson`.
  static Map<String, dynamic> _veilleArticleToContentJson(
    Map<String, dynamic> article,
  ) {
    return {
      'id': article['id'],
      'title': article['title'],
      'url': article['url'],
      'description': article['description'],
      'published_at': article['published_at'],
      'thumbnail_url': article['thumbnail_url'],
      'source': article['source'],
      'topics': article['topics'] ?? const [],
      // Content.fromJson tolère ces champs absents — fallback to defaults.
    };
  }
}

final fluxContinuRepositoryProvider = Provider<FluxContinuRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FluxContinuRepository(apiClient);
});
