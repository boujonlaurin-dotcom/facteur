import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../lettres/providers/letters_provider.dart';
import '../models/topic_models.dart';
import '../repositories/topic_repository.dart';

// Repository provider
final topicRepositoryProvider = Provider<TopicRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return TopicRepository(apiClient);
});

// Main topics provider
final customTopicsProvider =
    AsyncNotifierProvider<CustomTopicsNotifier, List<UserTopicProfile>>(() {
  return CustomTopicsNotifier();
});

class CustomTopicsNotifier extends AsyncNotifier<List<UserTopicProfile>> {
  /// Serializes mutations to prevent overlapping optimistic state snapshots.
  Future<void>? _pendingOperation;

  /// Runs [action] sequentially: waits for any pending operation to complete
  /// before starting, preventing race conditions in optimistic updates.
  Future<T> _serialized<T>(Future<T> Function() action) async {
    while (_pendingOperation != null) {
      try {
        await _pendingOperation;
      } catch (_) {
        // Previous op failed, proceed with ours
      }
    }
    final completer = Completer<T>();
    _pendingOperation = completer.future.then((_) {}).catchError((_) {});
    try {
      final result = await action();
      completer.complete(result);
      return result;
    } catch (e) {
      completer.completeError(e);
      rethrow;
    } finally {
      _pendingOperation = null;
    }
  }

  @override
  FutureOr<List<UserTopicProfile>> build() async {
    // Watch auth state to handle logout/user change
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      return [];
    }

    final sw = Stopwatch()..start();
    final repo = ref.read(topicRepositoryProvider);
    final topics = await repo.getTopics();
    sw.stop();
    print('[PERF] customTopicsProvider.build(): ${sw.elapsedMilliseconds}ms (${topics.length} topics)');
    return topics;
  }

  /// Follow a new topic by name.
  /// Optimistic: adds a placeholder immediately, replaces with server response.
  /// [slugParent] allows immediate slug matching before the API responds.
  /// [priorityMultiplier] restores a specific priority (e.g. undo after unfollow).
  Future<UserTopicProfile?> followTopic(String name, {String? slugParent, double? priorityMultiplier}) =>
      _serialized(() async {
    final repo = ref.read(topicRepositoryProvider);

    // Snapshot current state for rollback
    final previousState = state;

    // Optimistic: create a placeholder entry with slugParent for correct matching
    final placeholder = UserTopicProfile(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      slugParent: slugParent,
      priorityMultiplier: priorityMultiplier ?? 1.0,
    );

    if (state.hasValue) {
      state = AsyncData([...state.value!, placeholder]);
    } else {
      // Provider still loading — start with placeholder so UI updates immediately
      state = AsyncData([placeholder]);
    }

    try {
      final created = await repo.followTopic(name, priorityMultiplier: priorityMultiplier);

      // Replace placeholder with server-enriched profile
      if (state.hasValue) {
        final updated = state.value!
            .map((t) => t.id == placeholder.id ? created : t)
            .toList();
        state = AsyncData(updated);
      } else {
        state = AsyncData([created]);
      }
      // Sprint 2 PR1 — fire after server-side create so we log the real slug.
      unawaited(ref.read(analyticsServiceProvider).trackSubtopicAdded(
            subtopicSlug: created.slugParent ?? created.name,
            origin: 'custom_topics',
          ));
      // Story 19.1 — repaint l'avancement Lettres si une action devient validée.
      unawaited(ref.read(lettersProvider.notifier).silentRefresh());
      return created;
    } catch (e) {
      // Rollback
      state = previousState;
      rethrow;
    }
  });

  /// Unfollow a topic by ID.
  /// Optimistic: removes immediately, rolls back on error.
  Future<void> unfollowTopic(String topicId) => _serialized(() async {
    final repo = ref.read(topicRepositoryProvider);

    final previousState = state;
    // Snapshot slug before removing so analytics gets the real value even
    // when the optimistic update has already dropped the topic from state.
    final removed = previousState.value?.firstWhere(
      (t) => t.id == topicId,
      orElse: () => UserTopicProfile(id: topicId, name: '', slugParent: null),
    );

    if (state.hasValue) {
      state = AsyncData(
        state.value!.where((t) => t.id != topicId).toList(),
      );
    }

    try {
      await repo.unfollowTopic(topicId);
      if (removed != null) {
        unawaited(ref.read(analyticsServiceProvider).trackSubtopicRemoved(
              subtopicSlug: removed.slugParent ??
                  (removed.name.isNotEmpty ? removed.name : topicId),
              origin: 'custom_topics',
            ));
      }
    } catch (e) {
      state = previousState;
      rethrow;
    }
  });

  /// Update priority multiplier for a topic.
  /// Optimistic: updates the value immediately, rolls back on error.
  Future<void> updatePriority(String topicId, double newPriority) => _serialized(() async {
    final repo = ref.read(topicRepositoryProvider);

    final previousState = state;
    if (state.hasValue) {
      state = AsyncData([
        for (final topic in state.value!)
          if (topic.id == topicId)
            topic.copyWith(priorityMultiplier: newPriority)
          else
            topic,
      ]);
    }

    try {
      final updated = await repo.updateTopicPriority(topicId, newPriority);

      // Replace with server response (may have updated composite_score)
      if (state.hasValue) {
        state = AsyncData([
          for (final topic in state.value!)
            if (topic.id == topicId) updated else topic,
        ]);
      }
    } catch (e) {
      state = previousState;
      rethrow;
    }
  });

  /// Toggle `excluded_from_serein` for a topic.
  /// Optimistic: updates state immediately, rolls back on error.
  Future<void> setExcludedFromSerein(String topicId, bool excluded) =>
      _serialized(() async {
    final repo = ref.read(topicRepositoryProvider);

    final previousState = state;
    if (state.hasValue) {
      state = AsyncData([
        for (final topic in state.value!)
          if (topic.id == topicId)
            topic.copyWith(excludedFromSerein: excluded)
          else
            topic,
      ]);
    }

    try {
      final updated = await repo.updateTopicSereinExclusion(topicId, excluded);
      if (state.hasValue) {
        state = AsyncData([
          for (final topic in state.value!)
            if (topic.id == topicId) updated else topic,
        ]);
      }
    } catch (e) {
      state = previousState;
      rethrow;
    }
  });

  /// Force refresh from server.
  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(topicRepositoryProvider);
      final topics = await repo.getTopics();
      state = AsyncData(topics);
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }

  /// Check if a topic name is already followed (case-insensitive).
  bool isFollowed(String name) {
    if (!state.hasValue) return false;
    return state.value!.any(
      (t) => t.name.toLowerCase() == name.toLowerCase(),
    );
  }

  /// Check if an entity is already followed by canonical name (case-insensitive).
  bool isEntityFollowed(String canonicalName) {
    if (!state.hasValue) return false;
    return state.value!.any(
      (t) => t.canonicalName?.toLowerCase() == canonicalName.toLowerCase(),
    );
  }

  /// Follow an entity by name and type.
  /// Optimistic: adds a placeholder immediately, replaces with server response.
  Future<UserTopicProfile?> followEntity(
    String name,
    String entityType, {
    String? slugParent,
  }) =>
      _serialized(() async {
    final repo = ref.read(topicRepositoryProvider);
    final previousState = state;

    final placeholder = UserTopicProfile(
      id: 'temp_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      slugParent: slugParent,
      entityType: entityType,
      canonicalName: name,
    );

    if (state.hasValue) {
      state = AsyncData([...state.value!, placeholder]);
    } else {
      state = AsyncData([placeholder]);
    }

    try {
      final created = await repo.followEntity(name, entityType);
      if (state.hasValue) {
        final updated = state.value!
            .map((t) => t.id == placeholder.id ? created : t)
            .toList();
        state = AsyncData(updated);
      } else {
        state = AsyncData([created]);
      }
      // Story 19.1 — repaint l'avancement Lettres si une action devient validée.
      unawaited(ref.read(lettersProvider.notifier).silentRefresh());
      return created;
    } catch (e) {
      state = previousState;
      rethrow;
    }
  });
}

// Topic suggestions provider (parameterized by optional theme slug)
final topicSuggestionsProvider =
    FutureProvider.family<List<String>, String?>((ref, theme) async {
  final repo = ref.watch(topicRepositoryProvider);
  return repo.getTopicSuggestions(theme: theme);
});

// Popular entities provider (parameterized by optional theme slug)
final popularEntitiesProvider =
    FutureProvider.family<List<PopularEntity>, String?>((ref, theme) async {
  final repo = ref.watch(topicRepositoryProvider);
  return repo.getPopularEntities(theme: theme);
});
