import 'dart:async';

import 'package:flutter/foundation.dart';
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
///
/// **Fail-open contract:** Any error (auth, network, API 5xx, Supabase not
/// yet initialized, JSON shape mismatch) resolves to an empty
/// [CommunityCarousels]. The carousels are a pure enhancement on top of the
/// core feed/digest experience — they must NEVER surface an AsyncError to
/// parent widgets, otherwise an uncaught exception in the build tree can
/// block the entire Feed/Digest from rendering.
final communityCarouselProvider =
    FutureProvider.autoDispose<CommunityCarousels>((ref) async {
  // Defensive: if authState itself throws (rare but possible during
  // boot if Hive/Supabase isn't ready), treat as unauthenticated.
  try {
    final authState = ref.watch(authStateProvider);
    if (!authState.isAuthenticated) {
      return const CommunityCarousels();
    }
  } catch (e) {
    debugPrint('communityCarouselProvider: authState read failed: $e');
    return const CommunityCarousels();
  }

  try {
    // `ref.read(apiClientProvider)` is wrapped because apiClientProvider
    // synchronously reads `Supabase.instance.client` — which throws
    // LateInitializationError if the provider tree rebuilds before
    // Supabase.initialize() has completed during boot.
    final apiClient = ref.read(apiClientProvider);
    final response = await apiClient.dio
        .get<dynamic>('community/recommendations')
        .timeout(const Duration(seconds: 5));

    if (response.statusCode == 200 && response.data is Map) {
      final data = response.data as Map<String, dynamic>;

      final feedItems = (data['feed_carousel'] as List<dynamic>?)
              ?.map((e) =>
                  CommunityCarouselItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      final digestItems = (data['digest_carousel'] as List<dynamic>?)
              ?.map((e) =>
                  CommunityCarouselItem.fromJson(e as Map<String, dynamic>))
              .toList() ??
          [];

      return CommunityCarousels(
        feedCarousel: feedItems,
        digestCarousel: digestItems,
      );
    }
  } catch (e) {
    // Fail silently — carousel is optional enhancement.
    // Logged at debug level only (Sentry capture happens via Dio interceptor).
    debugPrint('communityCarouselProvider: $e');
  }

  return const CommunityCarousels();
});
