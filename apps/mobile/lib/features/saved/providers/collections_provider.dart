import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../../feed/models/content_model.dart';
import '../models/collection_model.dart';
import '../repositories/collections_repository.dart';

// Repository provider
final collectionsRepositoryProvider = Provider<CollectionsRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return CollectionsRepository(apiClient);
});

// Collections list provider
final collectionsProvider =
    AsyncNotifierProvider<CollectionsNotifier, List<Collection>>(() {
  return CollectionsNotifier();
});

class CollectionsNotifier extends AsyncNotifier<List<Collection>> {
  @override
  FutureOr<List<Collection>> build() async {
    final authState = ref.watch(authStateProvider);
    if (!authState.isAuthenticated) return [];

    final repo = ref.read(collectionsRepositoryProvider);
    return repo.listCollections();
  }

  Future<Collection> createCollection(String name) async {
    final repo = ref.read(collectionsRepositoryProvider);
    final collection = await repo.createCollection(name);

    // Refresh list
    final current = state.value ?? [];
    state = AsyncData([...current, collection]);

    return collection;
  }

  Future<void> updateCollection(String collectionId, String name) async {
    final repo = ref.read(collectionsRepositoryProvider);
    final updated = await repo.updateCollection(collectionId, name);

    // Update in list
    final current = state.value ?? [];
    final idx = current.indexWhere((c) => c.id == collectionId);
    if (idx >= 0) {
      final updatedList = List<Collection>.from(current);
      updatedList[idx] = updated;
      state = AsyncData(updatedList);
    }
  }

  Future<void> deleteCollection(String collectionId) async {
    final repo = ref.read(collectionsRepositoryProvider);
    await repo.deleteCollection(collectionId);

    // Remove from list
    final current = state.value ?? [];
    state = AsyncData(current.where((c) => c.id != collectionId).toList());
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    try {
      final repo = ref.read(collectionsRepositoryProvider);
      final collections = await repo.listCollections();
      state = AsyncData(collections);
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }
}

// Collection detail provider (articles in a specific collection)
final collectionDetailProvider = AsyncNotifierProvider.family<
    CollectionDetailNotifier, List<Content>, String>(() {
  return CollectionDetailNotifier();
});

class CollectionDetailNotifier
    extends FamilyAsyncNotifier<List<Content>, String> {
  int _page = 1;
  static const int _limit = 20;
  bool _hasNext = true;
  bool _isLoadingMore = false;
  String _sort = 'recent';

  bool get hasNext => _hasNext;
  bool get isLoadingMore => _isLoadingMore;
  String get sort => _sort;

  @override
  FutureOr<List<Content>> build(String arg) async {
    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;
    _sort = 'recent';

    return _fetchPage(page: 1);
  }

  Future<List<Content>> _fetchPage({required int page}) async {
    final repo = ref.read(collectionsRepositoryProvider);
    final items = await repo.getCollectionItems(
      collectionId: arg,
      limit: _limit,
      offset: (page - 1) * _limit,
      sort: _sort,
    );
    _hasNext = items.length >= _limit;
    return items;
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || !_hasNext || state.isLoading) return;

    _isLoadingMore = true;
    try {
      final nextPage = _page + 1;
      final newItems = await _fetchPage(page: nextPage);
      if (newItems.isNotEmpty) {
        _page = nextPage;
        final current = state.value ?? [];
        state = AsyncData([...current, ...newItems]);
      }
    } catch (e, stack) {
      state = AsyncError(e, stack);
    } finally {
      _isLoadingMore = false;
    }
  }

  Future<void> changeSort(String newSort) async {
    _sort = newSort;
    _page = 1;
    _hasNext = true;
    state = const AsyncLoading();

    try {
      final items = await _fetchPage(page: 1);
      state = AsyncData(items);
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }

  Future<void> removeItem(String contentId) async {
    final current = state.value ?? [];
    // Optimistic remove
    state = AsyncData(current.where((c) => c.id != contentId).toList());

    try {
      final repo = ref.read(collectionsRepositoryProvider);
      await repo.removeFromCollection(arg, contentId);
      // Refresh collections list to update counts
      ref.invalidate(collectionsProvider);
    } catch (e) {
      // Rollback
      state = AsyncData(current);
      rethrow;
    }
  }

  Future<void> refresh() async {
    _page = 1;
    _hasNext = true;
    _isLoadingMore = false;
    state = const AsyncLoading();

    try {
      final items = await _fetchPage(page: 1);
      state = AsyncData(items);
    } catch (e, stack) {
      state = AsyncError(e, stack);
    }
  }
}
