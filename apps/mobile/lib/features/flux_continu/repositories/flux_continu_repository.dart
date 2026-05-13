import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/api_client.dart';
import '../../../core/api/providers.dart';

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
}

final fluxContinuRepositoryProvider = Provider<FluxContinuRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FluxContinuRepository(apiClient);
});
