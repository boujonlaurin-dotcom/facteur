import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/auth/auth_state.dart';
import '../../feed/models/content_model.dart';
import '../../feed/providers/feed_provider.dart';

// Provider spécifique pour les contenus sauvegardés
final savedFeedProvider =
    AsyncNotifierProvider<SavedFeedNotifier, List<Content>>(() {
  return SavedFeedNotifier();
});

class SavedFeedNotifier extends AsyncNotifier<List<Content>> {
  int _page = 1;
  static const int _limit = 20;
  bool _hasNext = true;
  bool _isLoadingMore = false;

  bool get isLoadingMore => _isLoadingMore;
  bool get hasNext => _hasNext;

  @override
  FutureOr<List<Content>> build() async {
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      return [];
    }

    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;

    return _fetchPage(page: 1);
  }

  Future<List<Content>> _fetchPage({required int page}) async {
    final repository = ref.read(feedRepositoryProvider);
    final response = await repository.getFeed(
        page: page, limit: _limit, savedOnly: true // Force savedOnly
        );

    _hasNext = response.pagination.hasNext;
    return response.items;
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasNext || state.isLoading) return;

    _isLoadingMore = true;
    try {
      final nextPage = _page + 1;
      final newItems = await _fetchPage(page: nextPage);

      if (newItems.isNotEmpty) {
        _page = nextPage;
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
    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;
    state = const AsyncLoading();

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

    final updatedItems = List<Content>.from(currentItems);

    // Optimistic Remove (Unsave)
    updatedItems.removeWhere((c) => c.id == content.id);
    state = AsyncData(updatedItems);

    try {
      final repository = ref.read(feedRepositoryProvider);
      await repository.toggleSave(content.id, false);
      // Invalidate main feed so the item reappears there
      ref.invalidate(feedProvider);
    } catch (e) {
      await refresh(); // Revert
      rethrow;
    }
  }

  Future<void> undoRemove(Content content) async {
    final currentItems = state.value ?? [];

    // Add back to top (since we don't know original index easily without more logic)
    // Or sorted by updated_at?
    // Just add to top for visual feedback.

    final updatedItems = [content, ...currentItems];
    state = AsyncData(updatedItems);

    try {
      final repository = ref.read(feedRepositoryProvider);
      // Save = true
      await repository.toggleSave(content.id, true);
    } catch (e) {
      await refresh();
      rethrow;
    }
  }
}
