import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../models/content_model.dart';
import '../repositories/feed_repository.dart';
import '../repositories/personalization_repository.dart';
import '../../saved/providers/saved_feed_provider.dart';

// Provider du repository
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FeedRepository(apiClient);
});

// Provider des données du feed (Infinite Scroll)
class FeedState {
  final List<Content> items;

  FeedState({
    required this.items,
  });
}

// Provider des données du feed (Infinite Scroll + Briefing)
final feedProvider = AsyncNotifierProvider<FeedNotifier, FeedState>(() {
  return FeedNotifier();
});

class FeedNotifier extends AsyncNotifier<FeedState> {
  // Internal state for pagination
  int _page = 1;
  static const int _limit = 20;
  bool _hasNext = true;
  bool _isLoadingMore = false;
  String? _selectedFilter;
  String? _selectedTheme;
  final Set<String> _consumedContentIds =
      {}; // Track content being animated out

  bool get isLoadingMore => _isLoadingMore;
  bool get hasNext => _hasNext;
  String? get selectedFilter => _selectedFilter;
  String? get selectedTheme => _selectedTheme;

  @override
  FutureOr<FeedState> build() async {
    // Watch auth state to handle logout/user change
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      return FeedState(items: []);
    }

    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;
    _selectedFilter = null; // Reset filter on build/rebuild
    _selectedTheme = null;

    // Fetch initial page
    final response = await _fetchPage(page: 1);

    // Check if we need to load more immediately? No.

    return FeedState(items: response.items);
  }

  Future<void> setFilter(String? filter) async {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    _selectedTheme = null; // Theme et mode sont mutuellement exclusifs
    await refresh();
  }

  Future<void> setTheme(String? theme) async {
    if (_selectedTheme == theme) return;
    _selectedTheme = theme;
    _selectedFilter = null; // Theme et mode sont mutuellement exclusifs
    await refresh();
  }

  Future<FeedResponse> _fetchPage({required int page}) async {
    final repository = ref.read(feedRepositoryProvider);
    final response = await repository.getFeed(
        page: page,
        limit: _limit,
        mode: _selectedFilter,
        theme: _selectedTheme);

    // Update pagination state
    _hasNext = response.pagination.hasNext;

    return response;
  }

  Future<void> loadMore() async {
    // Prevent multiple calls or if no more data
    if (_isLoadingMore || !_hasNext || state.isLoading) return;

    _isLoadingMore = true;

    try {
      final nextPage = _page + 1;
      final response = await _fetchPage(page: nextPage);
      final newItems = response.items;

      if (newItems.isNotEmpty) {
        _page = nextPage;
        // Append new items to the existing list
        final currentItems = state.value?.items ?? [];

        state = AsyncData(FeedState(
          items: [...currentItems, ...newItems],
        ));
      }
    } catch (e, stack) {
      state = AsyncError(e, stack);
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> refresh() async {
    // Reset pagination
    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;

    state = const AsyncLoading(); // Emitting loading state

    try {
      final response = await _fetchPage(page: 1);
      state = AsyncData(FeedState(items: response.items));
    } catch (e, stack) {
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  Future<void> toggleSave(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    final currentItems = currentState.items;
    final index = currentItems.indexWhere((c) => c.id == content.id);

    // Si l'index est -1, l'item a été archivé (ou absent)
    final bool currentlyInList = index != -1;
    final bool oldIsSaved =
        currentlyInList ? currentItems[index].isSaved : true;
    final bool newIsSaved = !oldIsSaved;

    final updatedItems = List<Content>.from(currentItems);

    if (newIsSaved) {
      if (currentlyInList) {
        updatedItems[index] = content.copyWith(isSaved: true);
      }
    } else {
      if (currentlyInList) {
        updatedItems[index] = content.copyWith(isSaved: false);
      }
    }

    // Mise à jour optimiste immédiate
    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.toggleSave(content.id, newIsSaved);
      // Invalidate SavedFeed so it refreshes when the user navigates there
      ref.invalidate(savedFeedProvider);
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  Future<void> toggleLike(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    final currentItems = currentState.items;
    final index = currentItems.indexWhere((c) => c.id == content.id);

    final bool currentlyInList = index != -1;
    final bool oldIsLiked =
        currentlyInList ? currentItems[index].isLiked : true;
    final bool newIsLiked = !oldIsLiked;

    final updatedItems = List<Content>.from(currentItems);

    if (currentlyInList) {
      updatedItems[index] = content.copyWith(isLiked: newIsLiked);
    }

    // Optimistic update
    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.toggleLike(content.id, newIsLiked);
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  Future<void> hideContent(Content content, HiddenReason reason) async {
    final currentState = state.value;
    if (currentState == null) return;

    final updatedItems = List<Content>.from(currentState.items);
    updatedItems.removeWhere((c) => c.id == content.id);

    // Optimistic remove
    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id, reason);
    } catch (e) {
      await refresh();
      rethrow;
    }
  }

  Future<void> muteSource(Content content) async {
    await muteSourceById(content.source.id);
  }

  Future<void> muteSourceById(String sourceId) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content from this source
    final updatedItems =
        currentState.items.where((c) => c.source.id != sourceId).toList();
    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteSource(sourceId);
    } catch (e) {
      print('FeedNotifier: muteSourceById failed for $sourceId: $e');
      // Story: On ignore l'erreur backend pour ne pas bloquer l'utilisateur
      // On ne rafraîchit pas pour éviter de faire réapparaître l'item brutalement
    }
  }

  Future<void> muteTheme(String theme) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content from this theme
    final updatedItems =
        currentState.items.where((c) => c.source.theme != theme).toList();
    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteTheme(theme);
    } catch (e) {
      print('FeedNotifier: muteTheme failed for $theme: $e');
      // On ignore l'erreur backend
    }
  }

  Future<void> muteTopic(String topic) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content matching this topic
    // Since topics are often derived from themes in the current version:
    final updatedItems = currentState.items.where((c) {
      final itemTopic = c.progressionTopic;
      return itemTopic != topic;
    }).toList();

    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteTopic(topic);
    } catch (e) {
      print('FeedNotifier: muteTopic failed for $topic: $e');
      // On ignore l'erreur backend
    }
  }

  Future<void> muteContentType(String contentType) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Optimistic remove of all content matching this content type
    final updatedItems = currentState.items
        .where((c) => c.contentType.name != contentType)
        .toList();

    state = AsyncData(FeedState(items: updatedItems));

    try {
      final repo = ref.read(personalizationRepositoryProvider);
      await repo.muteContentType(contentType);
    } catch (e) {
      print('FeedNotifier: muteContentType failed for $contentType: $e');
    }
  }

  /// Check if content is currently being consumed (animating out)
  bool isContentConsumed(String contentId) {
    return _consumedContentIds.contains(contentId);
  }

  /// Update a content item in the feed list (e.g. after detail screen changes).
  /// Preserves provider-managed fields like [status] (consumed marking).
  void updateContent(Content updated) {
    final currentState = state.value;
    if (currentState == null) return;

    final items = currentState.items.map((c) {
      if (c.id != updated.id) return c;
      return updated.copyWith(status: c.status);
    }).toList();
    state = AsyncData(FeedState(items: items));
  }

  Future<void> markContentAsConsumed(Content content) async {
    final currentState = state.value;
    if (currentState == null) return;

    // Check if it's in the feed items
    final feedIndex = currentState.items.indexWhere((c) => c.id == content.id);

    if (feedIndex != -1) {
      // Update the item status in the list directly
      final updatedItems = List<Content>.from(currentState.items);
      updatedItems[feedIndex] =
          updatedItems[feedIndex].copyWith(status: ContentStatus.consumed);

      state = AsyncData(FeedState(items: updatedItems));

      // Call Generic API immediately (Fire and forget)
      try {
        final repository = ref.read(feedRepositoryProvider);
        await repository.updateContentStatus(
            content.id, ContentStatus.consumed);
      } catch (e) {
        // Silent failure, state is already updated optimistically
      }
    }
  }
}
