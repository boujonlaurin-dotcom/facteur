import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../models/content_model.dart';
import '../repositories/feed_repository.dart';
import '../../saved/providers/saved_feed_provider.dart';

// Provider du repository
final feedRepositoryProvider = Provider<FeedRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return FeedRepository(apiClient);
});

// Provider des données du feed (Infinite Scroll)
final feedProvider = AsyncNotifierProvider<FeedNotifier, List<Content>>(() {
  return FeedNotifier();
});

class FeedNotifier extends AsyncNotifier<List<Content>> {
  // Internal state for pagination
  int _page = 1;
  static const int _limit = 20;
  bool _hasNext = true;
  bool _isLoadingMore = false;
  String? _selectedFilter;

  bool get isLoadingMore => _isLoadingMore;
  bool get hasNext => _hasNext;
  String? get selectedFilter => _selectedFilter;

  @override
  FutureOr<List<Content>> build() async {
    // Watch auth state to handle logout/user change
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      return [];
    }

    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;
    _selectedFilter = null; // Reset filter on build/rebuild

    return _fetchPage(page: 1);
  }

  Future<void> setFilter(String? filter) async {
    if (_selectedFilter == filter) return;
    _selectedFilter = filter;
    await refresh();
  }

  Future<List<Content>> _fetchPage({required int page}) async {
    final repository = ref.read(feedRepositoryProvider);
    final response = await repository.getFeed(
        page: page, limit: _limit, contentType: _selectedFilter);

    // Update pagination state
    _hasNext = response.pagination.hasNext;

    return response.items;
  }

  Future<void> loadMore() async {
    // Prevent multiple calls or if no more data
    if (_isLoadingMore || !_hasNext || state.isLoading) return;

    // Use a local flag to avoid rebuilding the main state with loading
    // We want the UI to show the list + a loading indicator at the bottom
    _isLoadingMore = true;
    // Notify listeners that we are loading more (UI can check notifier.isLoadingMore)
    // Actually, AsyncNotifier doesn't notify on property change unless we change state.
    // So we might need to handle the "loading more" UI purely in the UI widget based on scroll,
    // or use a separate provider for loading status.
    // For simplicity, let's just proceed. The UI will call this method.

    try {
      final nextPage = _page + 1;
      final newItems = await _fetchPage(page: nextPage);

      if (newItems.isNotEmpty) {
        _page = nextPage;
        // Append new items to the existing list
        final currentItems = state.value ?? [];
        state = AsyncData([...currentItems, ...newItems]);
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

    // Set loading state while keeping previous data if possible
    // (AsyncLoading().copyWithPrevious(state) is implicit if we don't completely reset)
    // Actually, setting state = AsyncLoading() might clear data if not careful.
    // Ideally we want the UI to show the RefreshIndicator spinner, which is handled by the Future completion.
    // We can just re-fetch and update state.

    state = const AsyncLoading(); // Emitting loading state

    try {
      final newItems = await _fetchPage(page: 1);
      state = AsyncData(newItems);
    } catch (e, stack) {
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  Future<void> toggleSave(Content content) async {
    final currentItems = state.value;
    if (currentItems == null) return;

    final index = currentItems.indexWhere((c) => c.id == content.id);

    // Si l'index est -1, l'item a été archivé (optimistic remove)
    final bool currentlyInList = index != -1;
    final bool oldIsSaved =
        currentlyInList ? currentItems[index].isSaved : true;
    final bool newIsSaved = !oldIsSaved;

    final updatedItems = List<Content>.from(currentItems);

    if (newIsSaved) {
      if (currentlyInList) {
        updatedItems.removeAt(index);
      }
    } else {
      if (!currentlyInList) {
        // Undo / Unsave case: On réinsère l'item
        updatedItems.add(content.copyWith(isSaved: false));
        // On trie par date de publication (décroissant) pour maintenir un ordre cohérent
        // même si on n'a pas accès au score exact du serveur ici.
        updatedItems.sort((a, b) => b.publishedAt.compareTo(a.publishedAt));
      } else {
        updatedItems[index] = content.copyWith(isSaved: false);
      }
    }

    // Mise à jour optimiste immédiate
    state = AsyncData(updatedItems);

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.toggleSave(content.id, newIsSaved);
      // Invalidate SavedFeed so it refreshes when the user navigates there
      ref.invalidate(savedFeedProvider);
    } catch (e) {
      // En cas d'échec total, on recharge la liste depuis le serveur pour être sûr
      // (Alternativement on pourrait revert vers 'currentItems' mais le refresh est plus robuste)
      await refresh();
      rethrow;
    }
  }

  Future<void> hideContent(Content content, HiddenReason reason) async {
    final currentItems = state.value;
    if (currentItems == null) return;

    final updatedItems = List<Content>.from(currentItems);
    updatedItems.removeWhere((c) => c.id == content.id);

    // Optimistic remove
    state = AsyncData(updatedItems);

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.hideContent(content.id, reason);
    } catch (e) {
      // Revert/Refresh in case of error
      await refresh();
      rethrow;
    }
  }

  Future<void> markContentAsConsumed(Content content) async {
    final currentItems = state.value;
    if (currentItems == null) return;

    // Optimistic update: Remove from feed as it is consumed
    final updatedItems = List<Content>.from(currentItems);
    updatedItems.removeWhere((c) => c.id == content.id);

    state = AsyncData(updatedItems);

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.updateContentStatus(content.id, ContentStatus.consumed);
    } catch (e) {
      // Silent failure for tracking
    }
  }
}
