import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../../core/api/api_client.dart';
import '../../feed/repositories/personalization_repository.dart';
import '../models/source_model.dart';
import '../repositories/sources_repository.dart';

final sourcesRepositoryProvider = Provider<SourcesRepository>((ref) {
  return SourcesRepository(ApiClient(Supabase.instance.client));
});

final userSourcesProvider =
    AsyncNotifierProvider<UserSourcesNotifier, List<Source>>(() {
  return UserSourcesNotifier();
});

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
