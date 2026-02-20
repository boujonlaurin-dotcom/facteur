import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/ui/notification_service.dart';
import '../models/digest_models.dart';
import '../repositories/digest_repository.dart';

// Repository provider
final digestRepositoryProvider = Provider<DigestRepository>((ref) {
  final apiClient = ref.watch(apiClientProvider);
  return DigestRepository(apiClient);
});

// Digest state provider
final digestProvider =
    AsyncNotifierProvider<DigestNotifier, DigestResponse?>(() {
  return DigestNotifier();
});

class DigestNotifier extends AsyncNotifier<DigestResponse?> {
  bool _isCompleting = false;

  /// In-memory cache to avoid redundant API calls when navigating
  /// back to the digest screen within the same day.
  DigestResponse? _cachedDigest;
  String? _cachedDate; // ISO date string (YYYY-MM-DD) for cache invalidation

  /// Get today's date as a string for cache comparison.
  String get _todayDateString {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  @override
  FutureOr<DigestResponse?> build() async {
    // Watch auth state to handle logout/user change
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      _clearCache();
      return null;
    }

    // Return cached digest if available for today
    if (_cachedDigest != null && _cachedDate == _todayDateString) {
      return _cachedDigest;
    }

    // Load digest on initialization
    return await _loadDigest();
  }

  Future<DigestResponse> _loadDigest({DateTime? date}) async {
    final repository = ref.read(digestRepositoryProvider);
    final digest = await repository.getDigest(date: date).timeout(
          const Duration(seconds: 45),
          onTimeout: () => throw TimeoutException(
            'Le chargement a pris trop de temps. Verifiez votre connexion et reessayez.',
          ),
        );
    // Update cache after successful API call
    _updateCache(digest);
    return digest;
  }

  Future<void> loadDigest({DateTime? date}) async {
    // Check cache for today's digest (no specific date requested)
    if (date == null &&
        _cachedDigest != null &&
        _cachedDate == _todayDateString) {
      state = AsyncData(_cachedDigest);
      return;
    }

    state = const AsyncLoading();
    try {
      final digest = await _loadDigest(date: date);
      state = AsyncData(digest);
    } catch (e, stack) {
      _clearCache();
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  Future<void> refreshDigest() async {
    if (state.isLoading) return;

    final currentDigest = state.value;
    if (currentDigest == null) {
      await loadDigest();
      return;
    }

    state = const AsyncLoading();
    try {
      final digest = await _loadDigest(date: currentDigest.targetDate);
      state = AsyncData(digest);
    } catch (e, stack) {
      _clearCache();
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  /// Force refresh: clears cache and re-fetches from API.
  /// Use when the user explicitly wants fresh data (e.g., pull-to-refresh).
  Future<void> forceRefresh() async {
    _clearCache();
    await loadDigest();
  }

  /// Force regenerate digest (deletes existing and creates new)
  Future<void> forceRegenerate() async {
    if (state.isLoading) return;

    // Keep previous data while loading to prevent UI from disappearing
    final previousData = state.value;
    state = const AsyncLoading();

    try {
      final repository = ref.read(digestRepositoryProvider);
      final digest = await repository.forceRegenerateDigest();
      _updateCache(digest);
      state = AsyncData(digest);
      NotificationService.showSuccess('Nouveau briefing généré !');
    } catch (e, stack) {
      // Restore previous data on error so UI doesn't disappear
      if (previousData != null) {
        state = AsyncData(previousData);
      } else {
        _clearCache();
        state = AsyncError(e, stack);
      }
      NotificationService.showError(
        'Erreur lors de la régénération du briefing',
      );
      rethrow;
    }
  }

  /// Update the in-memory cache with a new digest response.
  void _updateCache(DigestResponse digest) {
    _cachedDigest = digest;
    _cachedDate = _todayDateString;
  }

  /// Clear the in-memory cache (forces next load to call API).
  void _clearCache() {
    _cachedDigest = null;
    _cachedDate = null;
  }

  /// Met à jour l'état avec une nouvelle réponse (utilisé par DigestModeNotifier
  /// après régénération avec un nouveau mode).
  void updateFromResponse(DigestResponse digest) {
    _updateCache(digest);
    state = AsyncData(digest);
  }

  /// Apply an action to a digest item (like, unlike, read, save, not_interested, undo)
  Future<void> applyAction(String contentId, String action) async {
    final currentDigest = state.value;
    if (currentDigest == null) return;

    // Optimistic update — apply to flat items
    final updatedItems = currentDigest.items.map((item) {
      if (item.contentId == contentId) {
        return _applyActionToItem(item, action);
      }
      return item;
    }).toList();

    // Also update articles inside topics (dual-update for topics_v1)
    final updatedTopics = currentDigest.topics.map((topic) {
      final updatedArticles = topic.articles.map((article) {
        if (article.contentId == contentId) {
          return _applyActionToItem(article, action);
        }
        return article;
      }).toList();
      return topic.copyWith(articles: updatedArticles);
    }).toList();

    final updatedDigest = currentDigest.copyWith(
      items: updatedItems,
      topics: updatedTopics,
    );
    state = AsyncData(updatedDigest);
    // Optimistically update cache so navigating away and back reflects the action
    _updateCache(updatedDigest);

    // Call API
    try {
      final repository = ref.read(digestRepositoryProvider);
      await repository.applyAction(
        digestId: currentDigest.digestId,
        contentId: contentId,
        action: action,
      );

      // Track content_interaction analytics event (unified schema)
      _trackContentInteraction(
        action: action,
        item: currentDigest.items.firstWhere(
          (i) => i.contentId == contentId,
          orElse: () => currentDigest.items.first,
        ),
        position:
            currentDigest.items.indexWhere((i) => i.contentId == contentId) + 1,
      );

      // Trigger haptic feedback on success
      await _triggerHaptic(action);
      _showActionNotification(action);

      // Check for completion
      _checkAndHandleCompletion();
    } catch (e) {
      // Rollback on error — restore original state and cache
      state = AsyncData(currentDigest);
      _updateCache(currentDigest);
      NotificationService.showError('Erreur lors de l\'action');
      rethrow;
    }
  }

  /// Sync a digest item's state from the detail screen (local only, no API).
  void syncItemFromDetail(String contentId,
      {required bool isSaved, String? noteText}) {
    final currentDigest = state.value;
    if (currentDigest == null) return;

    DigestItem updateItem(DigestItem item) {
      if (item.contentId == contentId) {
        return item.copyWith(isSaved: isSaved, noteText: noteText);
      }
      return item;
    }

    final updatedItems = currentDigest.items.map(updateItem).toList();
    final updatedTopics = currentDigest.topics.map((topic) {
      return topic.copyWith(articles: topic.articles.map(updateItem).toList());
    }).toList();

    final updatedDigest = currentDigest.copyWith(
      items: updatedItems,
      topics: updatedTopics,
    );
    state = AsyncData(updatedDigest);
    _updateCache(updatedDigest);
  }

  /// Undo an action on a digest item
  Future<void> undoAction(String contentId) async {
    await applyAction(contentId, 'undo');
  }

  /// Complete the digest
  Future<void> completeDigest() async {
    final currentDigest = state.value;
    if (currentDigest == null || currentDigest.isCompleted || _isCompleting) {
      return;
    }

    _isCompleting = true;

    try {
      final repository = ref.read(digestRepositoryProvider);
      await repository.completeDigest(currentDigest.digestId);

      // Trigger celebratory haptic
      await HapticFeedback.heavyImpact();

      // Update local state and cache
      final completedDigest = currentDigest.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
      );
      state = AsyncData(completedDigest);
      _updateCache(completedDigest);

      // Show completion notification
      NotificationService.showSuccess('Briefing terminé !');
    } catch (e) {
      // ignore: avoid_print
      print('DigestNotifier: completeDigest failed: $e');
      // Don't rethrow - completion failure shouldn't block UI
    } finally {
      _isCompleting = false;
    }
  }

  /// Apply an action mutation to a DigestItem's flags.
  DigestItem _applyActionToItem(DigestItem item, String action) {
    switch (action) {
      case 'like':
        return item.copyWith(isLiked: true);
      case 'unlike':
        return item.copyWith(isLiked: false);
      case 'read':
        return item.copyWith(isRead: true, isDismissed: false);
      case 'save':
        return item.copyWith(isSaved: true);
      case 'unsave':
        return item.copyWith(isSaved: false);
      case 'not_interested':
        return item.copyWith(isDismissed: true, isRead: false);
      case 'undo':
        return item.copyWith(
            isRead: false, isSaved: false, isLiked: false, isDismissed: false);
      default:
        return item;
    }
  }

  /// Get the count of processed units (topics covered OR items processed)
  int get processedCount {
    final digest = state.value;
    if (digest == null) return 0;
    if (digest.usesTopics) return digest.coveredTopicCount;
    return digest.items
        .where((item) => item.isRead || item.isDismissed || item.isSaved)
        .length;
  }

  /// Total units for progress denominator
  int get totalCount {
    final digest = state.value;
    if (digest == null) return 0;
    if (digest.usesTopics) return digest.topics.length;
    return digest.items.length;
  }

  /// Get progress as a fraction (0.0 to 1.0)
  double get progress {
    final tc = totalCount;
    if (tc == 0) return 0.0;
    return processedCount / tc;
  }

  /// Check if all units are processed and trigger completion.
  void _checkAndHandleCompletion() {
    final digest = state.value;
    if (digest == null || digest.isCompleted) return;

    if (processedCount >= totalCount) {
      completeDigest();
    }
  }

  /// Track a content interaction event for analytics (unified schema).
  /// Maps UI action names to analytics action names.
  void _trackContentInteraction({
    required String action,
    required DigestItem item,
    required int position,
  }) {
    // Map UI action names to analytics action names
    final String analyticsAction;
    switch (action) {
      case 'like':
        analyticsAction = 'like';
      case 'unlike':
        // unlike is not a tracked interaction event
        return;
      case 'read':
        analyticsAction = 'read';
      case 'save':
        analyticsAction = 'save';
      case 'unsave':
        // unsave is not a tracked interaction event
        return;
      case 'not_interested':
        analyticsAction = 'dismiss';
      case 'undo':
        // undo is not a tracked interaction event
        return;
      default:
        return;
    }

    try {
      ref.read(analyticsServiceProvider).trackContentInteraction(
            action: analyticsAction,
            surface: 'digest',
            contentId: item.contentId,
            sourceId: item.source?.id ?? '',
            topics: item.topics,
            position: position,
            timeSpentSeconds: 0,
          );
    } catch (e) {
      // Fail silently — analytics should never block user actions
      // ignore: avoid_print
      print('DigestNotifier: analytics tracking failed: $e');
    }
  }

  /// Trigger haptic feedback based on action type
  Future<void> _triggerHaptic(String action) async {
    switch (action) {
      case 'like':
        await HapticFeedback.mediumImpact();
      case 'unlike':
        await HapticFeedback.lightImpact();
      case 'read':
        await HapticFeedback.mediumImpact();
      case 'save':
        await HapticFeedback.lightImpact();
      case 'unsave':
        await HapticFeedback.lightImpact();
      case 'not_interested':
        await HapticFeedback.lightImpact();
      case 'undo':
        await HapticFeedback.lightImpact();
      default:
        await HapticFeedback.lightImpact();
    }
  }

  /// Show notification for successful action
  void _showActionNotification(String action) {
    switch (action) {
      case 'like':
        // Silent — visual toggle is sufficient feedback
        break;
      case 'unlike':
        // Silent — visual toggle is sufficient feedback
        break;
      case 'read':
        // Silent tracking - no notification needed for automatic read
        break;
      case 'save':
        // Notification handled by DigestScreen._handleSave (with collection CTA)
        break;
      case 'unsave':
        // Silent — visual toggle is sufficient feedback
        break;
      case 'not_interested':
        // Silent — user will get specific feedback from the personalization sheet
        // after choosing to mute source or theme
        break;
      case 'undo':
        NotificationService.showInfo(
          'Action annulée',
          duration: const Duration(seconds: 2),
        );
    }
  }

  /// Update a specific item's state locally (for optimistic updates)
  void updateItemState(String contentId,
      {bool? isRead, bool? isSaved, bool? isLiked, bool? isDismissed}) {
    final currentDigest = state.value;
    if (currentDigest == null) return;

    DigestItem applyFlags(DigestItem item) => item.copyWith(
          isRead: isRead ?? item.isRead,
          isSaved: isSaved ?? item.isSaved,
          isLiked: isLiked ?? item.isLiked,
          isDismissed: isDismissed ?? item.isDismissed,
        );

    final updatedItems = currentDigest.items.map((item) {
      return item.contentId == contentId ? applyFlags(item) : item;
    }).toList();

    final updatedTopics = currentDigest.topics.map((topic) {
      final updatedArticles = topic.articles.map((article) {
        return article.contentId == contentId ? applyFlags(article) : article;
      }).toList();
      return topic.copyWith(articles: updatedArticles);
    }).toList();

    final updatedDigest = currentDigest.copyWith(
      items: updatedItems,
      topics: updatedTopics,
    );
    state = AsyncData(updatedDigest);
    _updateCache(updatedDigest);
  }
}
