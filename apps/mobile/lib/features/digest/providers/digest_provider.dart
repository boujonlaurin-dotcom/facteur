import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
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

  @override
  FutureOr<DigestResponse?> build() async {
    // Watch auth state to handle logout/user change
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      return null;
    }

    // Load digest on initialization
    return await _loadDigest();
  }

  Future<DigestResponse> _loadDigest({DateTime? date}) async {
    final repository = ref.read(digestRepositoryProvider);
    return await repository.getDigest(date: date);
  }

  Future<void> loadDigest({DateTime? date}) async {
    state = const AsyncLoading();
    try {
      final digest = await _loadDigest(date: date);
      state = AsyncData(digest);
    } catch (e, stack) {
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
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  /// Force regenerate digest (deletes existing and creates new)
  Future<void> forceRegenerate() async {
    // ignore: avoid_print
    print(
        'DigestNotifier: forceRegenerate called - isLoading=${state.isLoading}');

    if (state.isLoading) {
      // ignore: avoid_print
      print('DigestNotifier: Already loading, returning early');
      return;
    }

    // Keep previous data while loading to prevent UI from disappearing
    final previousData = state.value;
    // ignore: avoid_print
    print('DigestNotifier: Setting state to AsyncLoading');
    state = const AsyncLoading();

    try {
      // ignore: avoid_print
      print('DigestNotifier: Calling repository.forceRegenerateDigest()');
      final repository = ref.read(digestRepositoryProvider);
      final digest = await repository.forceRegenerateDigest();
      // ignore: avoid_print
      print(
          'DigestNotifier: Repository call successful, setting state to AsyncData');
      state = AsyncData(digest);
      // ignore: avoid_print
      print('DigestNotifier: Showing success notification');
      NotificationService.showSuccess('Nouveau briefing généré !');
      // ignore: avoid_print
      print('DigestNotifier: forceRegenerate completed successfully');
    } catch (e, stack) {
      // ignore: avoid_print
      print('DigestNotifier: ERROR - $e\n$stack');
      // Restore previous data on error so UI doesn't disappear
      if (previousData != null) {
        // ignore: avoid_print
        print('DigestNotifier: Restoring previous data');
        state = AsyncData(previousData);
      } else {
        // ignore: avoid_print
        print('DigestNotifier: Setting error state');
        state = AsyncError(e, stack);
      }
      // ignore: avoid_print
      print('DigestNotifier: Showing error notification');
      NotificationService.showError(
        'Erreur lors de la régénération du briefing',
      );
      rethrow;
    }
  }

  /// Apply an action to a digest item (read, save, not_interested, undo)
  Future<void> applyAction(String contentId, String action) async {
    final currentDigest = state.value;
    if (currentDigest == null) return;

    // Optimistic update
    final updatedItems = currentDigest.items.map((item) {
      if (item.contentId == contentId) {
        switch (action) {
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
                isRead: false, isSaved: false, isDismissed: false);
          default:
            return item;
        }
      }
      return item;
    }).toList();

    state = AsyncData(currentDigest.copyWith(items: updatedItems));

    // Call API
    try {
      final repository = ref.read(digestRepositoryProvider);
      await repository.applyAction(
        digestId: currentDigest.digestId,
        contentId: contentId,
        action: action,
      );

      // Trigger haptic feedback on success
      await _triggerHaptic(action);
      _showActionNotification(action);

      // Check for completion
      _checkAndHandleCompletion();
    } catch (e) {
      // Rollback on error
      state = AsyncData(currentDigest);
      NotificationService.showError('Erreur lors de l\'action');
      rethrow;
    }
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

      // Update local state
      state = AsyncData(currentDigest.copyWith(
        isCompleted: true,
        completedAt: DateTime.now(),
      ));

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

  /// Get the count of processed items (read, dismissed, or saved)
  int get processedCount {
    final digest = state.value;
    if (digest == null) return 0;
    return digest.items
        .where((item) => item.isRead || item.isDismissed || item.isSaved)
        .length;
  }

  /// Get progress as a fraction (0.0 to 1.0)
  double get progress {
    final digest = state.value;
    if (digest == null || digest.items.isEmpty) return 0.0;
    return processedCount / digest.items.length;
  }

  /// Check if all items are processed and trigger completion
  void _checkAndHandleCompletion() {
    final digest = state.value;
    if (digest == null || digest.isCompleted) return;

    final allProcessed = digest.items
        .every((item) => item.isRead || item.isDismissed || item.isSaved);
    if (allProcessed) {
      completeDigest();
    }
  }

  /// Trigger haptic feedback based on action type
  Future<void> _triggerHaptic(String action) async {
    switch (action) {
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
      case 'read':
        // Silent tracking - no notification needed for automatic read
        break;
      case 'save':
        NotificationService.showInfo(
          'Article sauvegardé',
          duration: const Duration(seconds: 2),
        );
      case 'unsave':
        NotificationService.showInfo(
          'Article retiré des sauvegardes',
          duration: const Duration(seconds: 2),
        );
      case 'not_interested':
        NotificationService.showInfo(
          'Source masquée',
          duration: const Duration(seconds: 2),
        );
      case 'undo':
        NotificationService.showInfo(
          'Action annulée',
          duration: const Duration(seconds: 2),
        );
    }
  }

  /// Update a specific item's state locally (for optimistic updates)
  void updateItemState(String contentId,
      {bool? isRead, bool? isSaved, bool? isDismissed}) {
    final currentDigest = state.value;
    if (currentDigest == null) return;

    final updatedItems = currentDigest.items.map((item) {
      if (item.contentId == contentId) {
        return item.copyWith(
          isRead: isRead ?? item.isRead,
          isSaved: isSaved ?? item.isSaved,
          isDismissed: isDismissed ?? item.isDismissed,
        );
      }
      return item;
    }).toList();

    state = AsyncData(currentDigest.copyWith(items: updatedItems));
  }
}
