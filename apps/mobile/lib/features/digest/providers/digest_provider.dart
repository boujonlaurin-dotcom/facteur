import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/providers.dart';
import '../../../core/auth/auth_state.dart';
import '../../../core/providers/analytics_provider.dart';
import '../../../core/services/push_notification_service.dart';
import '../../../core/services/widget_service.dart';
import '../../../core/ui/notification_service.dart';
import '../../onboarding/providers/onboarding_provider.dart';
import '../../settings/providers/notifications_settings_provider.dart';
import '../models/digest_models.dart';
import '../repositories/digest_repository.dart';
import 'serein_toggle_provider.dart';

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

/// Read-only snapshot of the dual digest cache (both Essentiel + Lecture
/// apaisée variants). Re-emits when [digestProvider] changes. Falls back to
/// the active digest from state when the dual cache hasn't been populated
/// yet — keeps the feed carousel resilient before /digest/both lands.
final dualDigestPreviewProvider =
    Provider<({DigestResponse? normal, DigestResponse? serein})>((ref) {
  final state = ref.watch(digestProvider);
  final notifier = ref.read(digestProvider.notifier);
  final normal = notifier.normalDigest ?? state.valueOrNull;
  return (normal: normal, serein: notifier.sereinDigest);
});

class DigestNotifier extends AsyncNotifier<DigestResponse?> {
  bool _isCompleting = false;

  /// Dual-digest cache: both normal and serein variants stored in memory
  /// for instant toggle without network calls.
  DigestResponse? _normalDigest;
  DigestResponse? _sereinDigest;
  String? _cachedDate; // ISO date string (YYYY-MM-DD) for cache invalidation

  DigestResponse? get normalDigest => _normalDigest;
  DigestResponse? get sereinDigest => _sereinDigest;

  /// Timer scheduled when a stale fallback digest is shown, to auto-refetch
  /// fresh content generated in the background.
  Timer? _staleFallbackRefetchTimer;

  /// Per-item reading timer: records the timestamp at which each digest item
  /// was first opened (action `read`). Read again when the user performs a
  /// follow-up action (save, like, dismiss) to compute `time_spent_seconds`
  /// for the analytics event. Capped at 1800s per item.
  final DigestItemReadingTimers _readingTimers = DigestItemReadingTimers();

  /// Number of consecutive stale-fallback refetch attempts that still came
  /// back stale. Capped by [_staleFallbackMaxAttempts] so a broken backend
  /// can't cause an indefinite polling loop on the mobile client.
  int _staleFallbackAttempts = 0;
  static const int _staleFallbackMaxAttempts = 5;

  /// Exponential backoff for the stale-fallback auto-refetch. Each entry is
  /// the delay before attempt N+1. If all attempts fail, the next manual
  /// refresh or app open will retry cleanly.
  static const List<Duration> _staleFallbackBackoff = [
    Duration(seconds: 20),
    Duration(seconds: 40),
    Duration(seconds: 80),
    Duration(seconds: 160),
    Duration(seconds: 300),
  ];

  /// Get today's date as a string for cache comparison.
  String get _todayDateString {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }

  /// Returns the active digest based on the serein toggle.
  DigestResponse? get _activeDigest {
    final isSerein = ref.read(sereinToggleProvider).enabled;
    if (isSerein) return _sereinDigest ?? _normalDigest;
    return _normalDigest;
  }

  @override
  FutureOr<DigestResponse?> build() async {
    // Cancel any in-flight stale-fallback timer when the notifier is
    // disposed (user logout, provider invalidation, app backgrounded). Without
    // this, the Timer holds a reference to `this` and fires after dispose,
    // leaking state and potentially stomping a fresh load.
    ref.onDispose(() {
      _staleFallbackRefetchTimer?.cancel();
      _staleFallbackRefetchTimer = null;
    });

    // Watch auth state to handle logout/user change
    final authState = ref.watch(authStateProvider);

    if (!authState.isAuthenticated || authState.user == null) {
      _clearCache();
      return null;
    }

    // Watch serein toggle to swap digest on toggle change
    ref.watch(sereinToggleProvider.select((s) => s.enabled));

    // Return cached digest if available for today
    if (_normalDigest != null && _cachedDate == _todayDateString) {
      return _activeDigest;
    }

    // Load both digests on initialization
    return await _loadBothDigests();
  }

  // Retry budget sized for the "new user just finished onboarding" flow:
  // the server pre-generates the digest during the 10s conclusion animation,
  // but the editorial LLM pipeline can take up to ~90s on cold start. 5
  // retries with escalating delays (~80s total) keep the mobile client
  // polling on the 202 contract until the digest is ready, without hammering
  // a server that's already working.
  static const _digestMaxRetries = 5;
  static const _digestRetryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 10),
    Duration(seconds: 15),
    Duration(seconds: 20),
    Duration(seconds: 30),
  ];

  Future<DigestResponse?> _loadBothDigests({DateTime? date}) async {
    final repository = ref.read(digestRepositoryProvider);

    for (var attempt = 0; attempt <= _digestMaxRetries; attempt++) {
      try {
        final dual = await repository.fetchBothDigests(date: date).timeout(
              const Duration(seconds: 45),
              onTimeout: () => throw TimeoutException(
                'Le chargement a pris trop de temps. Verifiez votre connexion et reessayez.',
              ),
            );
        _normalDigest = dual.normal;
        _sereinDigest = dual.serein;
        _cachedDate = _todayDateString;
        // Sync toggle with server preference
        ref.read(sereinToggleProvider.notifier).initFromApi(dual.sereinEnabled);
        // Push to home screen widget
        _syncWidget();
        // Update notification with dynamic topic keywords
        unawaited(_updateNotificationWithTopics());
        // If either variant was served as yesterday's stale fallback while
        // fresh content is being generated in background, schedule a silent
        // auto-refetch so the user sees today's digest without pulling.
        _maybeScheduleStaleFallbackRefetch();
        return _activeDigest;
      } on DigestPreparingException {
        // 202: digest is being generated in background, retry with longer delays
        if (attempt < _digestMaxRetries) {
          // ignore: avoid_print
          print(
              'DigestNotifier: 202 preparing, retry ${attempt + 1}/$_digestMaxRetries...');
          await Future<void>.delayed(_digestRetryDelays[attempt]);
          continue;
        }
        rethrow;
      } on DigestTimeoutException {
        // Backend a lui-même timeout — retry agressif = pression inutile sur
        // un upstream déjà wedgé + retries mobiles qui se chevauchent.
        // Max 1 retry avec un delay long pour laisser l'upstream se remettre.
        // Cf. docs/bugs/bug-infinite-load-requests.md.
        if (attempt < 1) {
          // ignore: avoid_print
          print(
              'DigestNotifier: 503 digest_generation_timeout, 1 retry only (attempt ${attempt + 1})...');
          await Future<void>.delayed(const Duration(seconds: 15));
          continue;
        }
        rethrow;
      } on DigestGenerationException {
        // Real 503 (backend raised HTTPException). Keep the retry budget
        // bounded to 3 so we don't hammer a genuinely failing server — the
        // "digest is being prepared" case is already handled by the 202 path
        // above, so a persistent 503 here signals a real problem.
        const maxGenerationRetries = 3;
        if (attempt < maxGenerationRetries) {
          // ignore: avoid_print
          print(
              'DigestNotifier: 503 error, retry ${attempt + 1}/$maxGenerationRetries...');
          await Future<void>.delayed(_digestRetryDelays[attempt]);
          continue;
        }
        rethrow;
      } on DigestNotFoundException {
        // /digest/both returned 404 — fall back to single digest
        try {
          final digest = await repository.getDigest(date: date);
          _normalDigest = digest;
          _cachedDate = _todayDateString;
          ref.read(sereinToggleProvider.notifier).initFromApi(false);
          unawaited(_updateNotificationWithTopics());
          _maybeScheduleStaleFallbackRefetch();
          return digest;
        } catch (_) {
          rethrow;
        }
      }
    }
    throw DigestGenerationException();
  }

  Future<void> loadDigest({DateTime? date}) async {
    if (date == null &&
        _normalDigest != null &&
        _cachedDate == _todayDateString) {
      state = AsyncData(_activeDigest);
      return;
    }

    state = const AsyncLoading();
    try {
      final digest = await _loadBothDigests(date: date);
      state = AsyncData(digest);
    } catch (e, stack) {
      _clearCache();
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  Future<void> refreshDigest() async {
    if (state.isLoading) return;

    state = const AsyncLoading();
    try {
      final digest = await _loadBothDigests();
      state = AsyncData(digest);
    } catch (e, stack) {
      _clearCache();
      state = AsyncError(e, stack);
      rethrow;
    }
  }

  /// Force refresh: clears cache and re-fetches from API.
  Future<void> forceRefresh() async {
    _clearCache();
    await loadDigest();
  }

  /// Force regenerate digest (deletes existing and creates new)
  Future<void> forceRegenerate() async {
    if (state.isLoading) return;

    final previousData = state.value;
    state = const AsyncLoading();

    try {
      final repository = ref.read(digestRepositoryProvider);
      final digest = await repository.forceRegenerateDigest();
      _normalDigest = digest;
      _cachedDate = _todayDateString;
      state = AsyncData(digest);
      NotificationService.showSuccess('Nouveau briefing généré !');
    } catch (e, stack) {
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

  /// Push current digest state to the home screen widget.
  void _syncWidget() {
    final digest = state.value;
    WidgetService.updateWidget(digest: digest);
  }

  /// Update the daily notification with topic keywords from the loaded digest.
  /// Uses the normal digest topics to build an engaging notification body.
  /// Only updates if push notifications are enabled in user settings.
  ///
  /// If the user has Serein mode enabled, a calmer notification copy is used
  /// to avoid triggering anxiety before reading.
  Future<void> _updateNotificationWithTopics() async {
    try {
      final settings = ref.read(notificationsSettingsProvider);
      if (!settings.pushEnabled) return;

      final digest = _normalDigest;
      if (digest == null) return;

      final isSerein = ref.read(sereinToggleProvider).enabled;
      final topTopics = digest.topics
          .map((t) => t.label.trim())
          .where((l) => l.isNotEmpty)
          .take(3)
          .toList();

      // Variante C (jour calme) hors v1 — Serein + variante A pour rester
      // cohérent avec le brief §6.1 (variante C = override manuel uniquement).
      final variant = (!isSerein && topTopics.isNotEmpty)
          ? NotifVariant.variantB
          : NotifVariant.variantA;

      await PushNotificationService().scheduleDailyDigestNotification(
        timeSlot: settings.timeSlot,
        variant: variant,
        teasers: variant == NotifVariant.variantB ? topTopics : null,
      );
      debugPrint(
        'DigestNotifier: Re-scheduled (variant: $variant, slot: ${settings.timeSlot})',
      );
    } catch (e, stack) {
      debugPrint('DigestNotifier: Failed to update notification: $e\n$stack');
    }
  }

  /// Clear the in-memory cache (forces next load to call API).
  void _clearCache() {
    _normalDigest = null;
    _sereinDigest = null;
    _cachedDate = null;
    _staleFallbackRefetchTimer?.cancel();
    _staleFallbackRefetchTimer = null;
    _staleFallbackAttempts = 0;
  }

  /// If the current normal or serein digest is marked as `is_stale_fallback`
  /// (yesterday's content being served while today's regenerates in the
  /// background), schedule a silent refetch so the fresh version appears
  /// without the user pulling to refresh.
  ///
  /// Uses exponential backoff and caps total attempts at
  /// [_staleFallbackMaxAttempts] — a prolonged backend outage will stop
  /// polling rather than spin forever. The counter resets as soon as a
  /// fresh (non-stale) response arrives or on manual cache clear.
  void _maybeScheduleStaleFallbackRefetch() {
    final isStale = (_normalDigest?.isStaleFallback ?? false) ||
        (_sereinDigest?.isStaleFallback ?? false);
    _staleFallbackRefetchTimer?.cancel();
    if (!isStale) {
      // Fresh response: reset the attempt budget so a future stale window
      // gets the full retry quota.
      _staleFallbackAttempts = 0;
      _staleFallbackRefetchTimer = null;
      return;
    }
    if (_staleFallbackAttempts >= _staleFallbackMaxAttempts) {
      // Budget exhausted — stop auto-polling. User-triggered refresh or
      // next app open will retry from scratch.
      _staleFallbackRefetchTimer = null;
      return;
    }
    final delay = _staleFallbackBackoff[
        _staleFallbackAttempts.clamp(0, _staleFallbackBackoff.length - 1)];
    _staleFallbackAttempts++;
    _staleFallbackRefetchTimer = Timer(delay, () async {
      // Only auto-refetch if still authenticated and same day, and the
      // current state is not loading (avoid stomping an in-flight request).
      if (state.isLoading) return;
      final stillStaleNormal = _normalDigest?.isStaleFallback ?? false;
      final stillStaleSerein = _sereinDigest?.isStaleFallback ?? false;
      if (!stillStaleNormal && !stillStaleSerein) return;
      try {
        // Invalidate cache and reload both variants silently.
        _cachedDate = null;
        final fresh = await _loadBothDigests();
        state = AsyncData(fresh);
      } catch (_) {
        // Silent failure: the next manual refresh or app open will retry.
      }
    });
  }

  /// Apply an action to a digest item (like, unlike, read, save, not_interested, report_not_serene, undo)
  Future<void> applyAction(String contentId, String action) async {
    final currentDigest = state.value;
    if (currentDigest == null) return;

    // Report not serene: separate API call, no optimistic state change
    if (action == 'report_not_serene') {
      try {
        final repository = ref.read(digestRepositoryProvider);
        await repository.reportNotSerene(contentId);
        await HapticFeedback.lightImpact();
        NotificationService.showSuccess('Merci, nous en prenons note');
      } catch (e) {
        NotificationService.showError('Erreur lors du signalement');
      }
      return;
    }

    // Start the per-item reading timer on first open so follow-up actions
    // (save/like/dismiss) can report an accurate time_spent_seconds.
    if (action == 'read') {
      _readingTimers.start(contentId);
    }

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

    // Also update pepite/coup_de_coeur if contentId matches (editorial_v1)
    final updatedPepite = currentDigest.pepite != null &&
            currentDigest.pepite!.contentId == contentId
        ? _applyActionToPepite(currentDigest.pepite!, action)
        : currentDigest.pepite;
    final updatedCoupDeCoeur = currentDigest.coupDeCoeur != null &&
            currentDigest.coupDeCoeur!.contentId == contentId
        ? _applyActionToCoupDeCoeur(currentDigest.coupDeCoeur!, action)
        : currentDigest.coupDeCoeur;

    final updatedDigest = currentDigest.copyWith(
      items: updatedItems,
      topics: updatedTopics,
      pepite: updatedPepite,
      coupDeCoeur: updatedCoupDeCoeur,
    );
    state = AsyncData(updatedDigest);
    // Optimistically update the active cache variant
    _updateActiveCache(updatedDigest);
    // Also apply action to the OTHER cached digest (same article may appear in both)
    _applyActionToOtherCache(contentId, action);

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

      // Push updated state to home screen widget
      _syncWidget();

      // Check for completion
      _checkAndHandleCompletion();
    } catch (e) {
      // Rollback on error — restore original state and cache
      state = AsyncData(currentDigest);
      _updateActiveCache(currentDigest);
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

    // Also sync pepite/coup_de_coeur
    final updatedPepite = currentDigest.pepite != null &&
            currentDigest.pepite!.contentId == contentId
        ? currentDigest.pepite!.copyWith(isSaved: isSaved)
        : currentDigest.pepite;
    final updatedCoupDeCoeur = currentDigest.coupDeCoeur != null &&
            currentDigest.coupDeCoeur!.contentId == contentId
        ? currentDigest.coupDeCoeur!.copyWith(isSaved: isSaved)
        : currentDigest.coupDeCoeur;

    final updatedDigest = currentDigest.copyWith(
      items: updatedItems,
      topics: updatedTopics,
      pepite: updatedPepite,
      coupDeCoeur: updatedCoupDeCoeur,
    );
    state = AsyncData(updatedDigest);
    _updateActiveCache(updatedDigest);
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
      _updateActiveCache(completedDigest);

      // Push completed state to home screen widget
      _syncWidget();

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

  /// Apply an action mutation to a PepiteResponse's flags.
  PepiteResponse _applyActionToPepite(PepiteResponse p, String action) {
    switch (action) {
      case 'like':
        return p.copyWith(isLiked: true);
      case 'unlike':
        return p.copyWith(isLiked: false);
      case 'read':
        return p.copyWith(isRead: true, isDismissed: false);
      case 'save':
        return p.copyWith(isSaved: true);
      case 'unsave':
        return p.copyWith(isSaved: false);
      case 'not_interested':
        return p.copyWith(isDismissed: true, isRead: false);
      case 'undo':
        return p.copyWith(
            isRead: false, isSaved: false, isLiked: false, isDismissed: false);
      default:
        return p;
    }
  }

  /// Apply an action mutation to a CoupDeCoeurResponse's flags.
  CoupDeCoeurResponse _applyActionToCoupDeCoeur(
      CoupDeCoeurResponse c, String action) {
    switch (action) {
      case 'like':
        return c.copyWith(isLiked: true);
      case 'unlike':
        return c.copyWith(isLiked: false);
      case 'read':
        return c.copyWith(isRead: true, isDismissed: false);
      case 'save':
        return c.copyWith(isSaved: true);
      case 'unsave':
        return c.copyWith(isSaved: false);
      case 'not_interested':
        return c.copyWith(isDismissed: true, isRead: false);
      case 'undo':
        return c.copyWith(
            isRead: false, isSaved: false, isLiked: false, isDismissed: false);
      default:
        return c;
    }
  }

  /// Get the count of processed units (topics covered OR items processed)
  int get processedCount {
    final digest = state.value;
    if (digest == null) return 0;
    if (digest.usesTopics) {
      var count = digest.coveredTopicCount;
      if (digest.usesEditorial) {
        final p = digest.pepite;
        if (p != null && (p.isRead || p.isSaved || p.isDismissed)) count++;
        final c = digest.coupDeCoeur;
        if (c != null && (c.isRead || c.isSaved || c.isDismissed)) count++;
      }
      return count;
    }
    return digest.items
        .where((item) => item.isRead || item.isDismissed || item.isSaved)
        .length;
  }

  /// Total units for progress denominator
  int get totalCount {
    final digest = state.value;
    if (digest == null) return 0;
    if (digest.usesTopics) {
      var count = digest.topics.length;
      if (digest.usesEditorial) {
        if (digest.pepite != null) count++;
        if (digest.coupDeCoeur != null) count++;
      }
      return count;
    }
    return digest.items.length;
  }

  /// Get progress as a fraction (0.0 to 1.0)
  double get progress {
    final tc = totalCount;
    if (tc == 0) return 0.0;
    return processedCount / tc;
  }

  /// Daily goal = what the UI displays in the progress bar. Matches the
  /// `min(totalCount, onboarding.dailyArticleCount)` formula used in
  /// digest_screen. Completion fires when the user hits this goal, even if
  /// extras (pépite / coup de cœur) are still unprocessed.
  int get goalCount {
    final tc = totalCount;
    if (tc == 0) return 0;
    final userPref =
        ref.read(onboardingProvider).answers.dailyArticleCount ?? 5;
    return tc < userPref ? tc : userPref;
  }

  /// Check if the daily goal is reached and trigger completion.
  void _checkAndHandleCompletion() {
    final digest = state.value;
    if (digest == null || digest.isCompleted) return;

    final goal = goalCount;
    if (goal > 0 && processedCount >= goal) {
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

    final timeSpentSeconds = _readingTimers.consume(item.contentId, action);

    try {
      ref.read(analyticsServiceProvider).trackContentInteraction(
            action: analyticsAction,
            surface: 'digest',
            contentId: item.contentId,
            sourceId: item.source?.id ?? '',
            topics: item.topics,
            position: position,
            timeSpentSeconds: timeSpentSeconds,
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

    // Also update pepite/coup_de_coeur
    final updatedPepite = currentDigest.pepite != null &&
            currentDigest.pepite!.contentId == contentId
        ? currentDigest.pepite!.copyWith(
            isRead: isRead ?? currentDigest.pepite!.isRead,
            isSaved: isSaved ?? currentDigest.pepite!.isSaved,
            isLiked: isLiked ?? currentDigest.pepite!.isLiked,
            isDismissed: isDismissed ?? currentDigest.pepite!.isDismissed,
          )
        : currentDigest.pepite;
    final updatedCoupDeCoeur = currentDigest.coupDeCoeur != null &&
            currentDigest.coupDeCoeur!.contentId == contentId
        ? currentDigest.coupDeCoeur!.copyWith(
            isRead: isRead ?? currentDigest.coupDeCoeur!.isRead,
            isSaved: isSaved ?? currentDigest.coupDeCoeur!.isSaved,
            isLiked: isLiked ?? currentDigest.coupDeCoeur!.isLiked,
            isDismissed: isDismissed ?? currentDigest.coupDeCoeur!.isDismissed,
          )
        : currentDigest.coupDeCoeur;

    final updatedDigest = currentDigest.copyWith(
      items: updatedItems,
      topics: updatedTopics,
      pepite: updatedPepite,
      coupDeCoeur: updatedCoupDeCoeur,
    );
    state = AsyncData(updatedDigest);
    _updateActiveCache(updatedDigest);
  }

  /// Update the active cache variant (normal or serein).
  void _updateActiveCache(DigestResponse digest) {
    final isSerein = ref.read(sereinToggleProvider).enabled;
    if (isSerein) {
      _sereinDigest = digest;
    } else {
      _normalDigest = digest;
    }
  }

  /// Apply an action to the OTHER cached digest (not the currently active one)
  /// so that toggling back preserves read/saved/liked state.
  void _applyActionToOtherCache(String contentId, String action) {
    final isSerein = ref.read(sereinToggleProvider).enabled;
    final otherDigest = isSerein ? _normalDigest : _sereinDigest;
    if (otherDigest == null) return;

    final updatedItems = otherDigest.items.map((item) {
      return item.contentId == contentId
          ? _applyActionToItem(item, action)
          : item;
    }).toList();

    final updatedTopics = otherDigest.topics.map((topic) {
      final updatedArticles = topic.articles.map((article) {
        return article.contentId == contentId
            ? _applyActionToItem(article, action)
            : article;
      }).toList();
      return topic.copyWith(articles: updatedArticles);
    }).toList();

    final updated = otherDigest.copyWith(
      items: updatedItems,
      topics: updatedTopics,
    );

    if (isSerein) {
      _normalDigest = updated;
    } else {
      _sereinDigest = updated;
    }
  }
}

/// Tracks the per-item reading timer so digest follow-up actions
/// (save/like/dismiss) can report an accurate `time_spent_seconds` to the
/// analytics pipeline. Start on first `read`, consume on subsequent action.
/// `read` itself is the open event and always reports 0 — the article viewer
/// captures the actual reading duration.
class DigestItemReadingTimers {
  final Map<String, DateTime> _openedAt = {};

  static const int maxSeconds = 1800;

  void start(String contentId, {DateTime? now}) {
    _openedAt[contentId] = now ?? DateTime.now();
  }

  int consume(String contentId, String action, {DateTime? now}) {
    if (action == 'read') return 0;
    final openedAt = _openedAt.remove(contentId);
    if (openedAt == null) return 0;
    final elapsed = (now ?? DateTime.now()).difference(openedAt).inSeconds;
    if (elapsed <= 0) return 0;
    return elapsed > maxSeconds ? maxSeconds : elapsed;
  }
}
