import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/api/api_client.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../models/smart_search_result.dart';
import '../models/source_model.dart';
import '../models/theme_source_model.dart';
import '../repositories/sources_repository.dart';

final sourcesRepositoryProvider = Provider<SourcesRepository>((ref) {
  return SourcesRepository(ApiClient(Supabase.instance.client));
});

typedef SmartSearchQuery = ({String query, String? contentType, bool expand});

final smartSearchProvider = FutureProvider.family<SmartSearchResponse,
    SmartSearchQuery>((ref, params) async {
  final trimmed = params.query.trim();
  if (trimmed.isEmpty) {
    return const SmartSearchResponse(queryNormalized: '', results: []);
  }
  final repository = ref.watch(sourcesRepositoryProvider);
  return repository.smartSearch(
    trimmed,
    contentType: params.contentType,
    expand: params.expand,
  );
});

final trendingSourcesProvider = FutureProvider<List<Source>>((ref) async {
  final repository = ref.watch(sourcesRepositoryProvider);
  return repository.getTrendingSources(limit: 10);
});

final themesFollowedProvider =
    FutureProvider<List<FollowedTheme>>((ref) async {
  final repository = ref.watch(sourcesRepositoryProvider);
  return repository.getThemesFollowed();
});

final sourcesByThemeProvider =
    FutureProvider.family<ThemeSourcesResponse, String>((ref, slug) async {
  final repository = ref.watch(sourcesRepositoryProvider);
  return repository.getSourcesByTheme(slug);
});

final userSourcesProvider =
    AsyncNotifierProvider<UserSourcesNotifier, List<Source>>(() {
  return UserSourcesNotifier();
});

/// Pépites — sources curées poussées dans le feed.
/// Liste vide si aucun trigger actif, rate-limit, ou cool-down côté backend.
final pepitesProvider =
    AsyncNotifierProvider<PepitesNotifier, List<Source>>(() {
  return PepitesNotifier();
});

class PepitesNotifier extends AsyncNotifier<List<Source>> {
  @override
  Future<List<Source>> build() async {
    final repository = ref.watch(sourcesRepositoryProvider);
    return repository.getPepites();
  }

  /// Dismiss le carousel côté backend + vide l'état local.
  Future<void> dismiss() async {
    final repository = ref.read(sourcesRepositoryProvider);
    state = const AsyncValue.data([]);
    try {
      await repository.dismissPepiteCarousel();
    } catch (e, stack) {
      // ignore: avoid_print
      print('PepitesNotifier: [ERROR] dismiss failed: $e\n$stack');
    }
  }

}

class UserSourcesNotifier extends AsyncNotifier<List<Source>> {
  @override
  Future<List<Source>> build() async {
    final repository = ref.watch(sourcesRepositoryProvider);
    return repository.getAllSources();
  }

  Future<void> toggleTrust(String sourceId, bool currentlyTrusted) async {
    final repository = ref.read(sourcesRepositoryProvider);

    // Optimistic Update
    final previousState = state;
    if (state.hasValue) {
      state = AsyncValue.data([
        for (final source in state.value!)
          if (source.id == sourceId)
            source.copyWith(isTrusted: !currentlyTrusted)
          else
            source
      ]);
    }

    try {
      // ignore: avoid_print
      print(
          'UserSourcesNotifier: Calling repository.trust/untrust for $sourceId...');

      if (currentlyTrusted) {
        await repository.untrustSource(sourceId);
      } else {
        await repository.trustSource(sourceId);
      }

      // ignore: avoid_print
      print('UserSourcesNotifier: Toggle success (persisted to DB)');
      // No need to re-fetch entire list: optimistic update is sufficient and avoids race conditions
    } catch (e, stack) {
      // ignore: avoid_print
      print('UserSourcesNotifier: [ERROR] Toggle failed: $e\n$stack');
      // Revert on error
      state = previousState;
    }
  }

  Future<void> updateWeight(String sourceId, double newMultiplier) async {
    final repository = ref.read(sourcesRepositoryProvider);

    // Optimistic Update
    final previousState = state;
    if (state.hasValue) {
      state = AsyncValue.data([
        for (final source in state.value!)
          if (source.id == sourceId)
            source.copyWith(priorityMultiplier: newMultiplier)
          else
            source
      ]);
    }

    try {
      await repository.updateSourceWeight(sourceId, newMultiplier);
    } catch (e, stack) {
      // ignore: avoid_print
      print('UserSourcesNotifier: [ERROR] updateWeight failed: $e\n$stack');
      state = previousState;
    }
  }

  Future<void> toggleSubscription(
      String sourceId, bool currentlySubscribed) async {
    final repository = ref.read(sourcesRepositoryProvider);

    // Optimistic Update
    final previousState = state;
    if (state.hasValue) {
      state = AsyncValue.data([
        for (final source in state.value!)
          if (source.id == sourceId)
            source.copyWith(hasSubscription: !currentlySubscribed)
          else
            source
      ]);
    }

    try {
      await repository.updateSourceSubscription(
          sourceId, !currentlySubscribed);
    } catch (e, stack) {
      // ignore: avoid_print
      print(
          'UserSourcesNotifier: [ERROR] toggleSubscription failed: $e\n$stack');
      state = previousState;
    }
  }

  Future<void> toggleMute(String sourceId, bool currentlyMuted) async {
    final personalizationRepo = ref.read(personalizationRepositoryProvider);

    // Optimistic Update
    final previousState = state;
    if (state.hasValue) {
      state = AsyncValue.data([
        for (final source in state.value!)
          if (source.id == sourceId)
            source.copyWith(
              isMuted: !currentlyMuted,
              // Muting auto-untrusts (backend does this too)
              isTrusted: !currentlyMuted ? false : source.isTrusted,
            )
          else
            source
      ]);
    }

    try {
      if (currentlyMuted) {
        await personalizationRepo.unmuteSource(sourceId);
      } else {
        await personalizationRepo.muteSource(sourceId);
      }
    } catch (e, stack) {
      // ignore: avoid_print
      print('UserSourcesNotifier: [ERROR] toggleMute failed: $e\n$stack');
      state = previousState;
    }
  }
}
