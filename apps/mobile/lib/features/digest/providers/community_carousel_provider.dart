import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../models/community_carousel_model.dart';

/// Holds both feed and digest community carousels.
class CommunityCarousels {
  final List<CommunityCarouselItem> feedCarousel;
  final List<CommunityCarouselItem> digestCarousel;

  const CommunityCarousels({
    this.feedCarousel = const [],
    this.digestCarousel = const [],
  });
}

/// Provider that fetches community recommendation carousels from the API.
/// Both the Feed and Digest screens can consume this.
final communityCarouselProvider =
    FutureProvider.autoDispose<CommunityCarousels>((ref) async {
  final authState = ref.watch(authStateProvider);
  if (!authState.isAuthenticated) {
    return const CommunityCarousels();
  }

  final apiClient = ref.read(apiClientProvider);

  try {
    final response = await apiClient.dio.get<dynamic>(
      'community/recommendations',
    );

    if (response.statusCode == 200 && response.data != null) {
      final data = response.data as Map<String, dynamic>;

      final feedItems = (data['feed_carousel'] as List<dynamic>?)
              ?.map(
                  (e) => CommunityCarouselItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      final digestItems = (data['digest_carousel'] as List<dynamic>?)
              ?.map(
                  (e) => CommunityCarouselItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      return CommunityCarousels(
        feedCarousel: feedItems,
        digestCarousel: digestItems,
      );
    }
  } catch (e) {
    // Fail silently — carousel is optional enhancement
    // ignore: avoid_print
    print('CommunityCarouselProvider: fetch failed: $e');
  }

  return const CommunityCarousels();
});
