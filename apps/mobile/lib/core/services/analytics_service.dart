import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:facteur/core/api/api_client.dart';

class AnalyticsService {
  final ApiClient _apiClient;
  String? _deviceId;
  String? _sessionId;
  DateTime? _sessionStartTime;

  AnalyticsService(this._apiClient);

  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _deviceId = prefs.getString('analytics_device_id');
    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString('analytics_device_id', _deviceId!);
    }
  }

  Future<void> startSession({bool isOrganic = true}) async {
    _sessionId = const Uuid().v4();
    _sessionStartTime = DateTime.now();

    await _logEvent('session_start', {
      'session_id': _sessionId,
      'is_organic': isOrganic,
      'platform': defaultTargetPlatform.toString(),
    });
  }

  Future<void> endSession() async {
    if (_sessionStartTime == null) return;

    final duration = DateTime.now().difference(_sessionStartTime!).inSeconds;

    await _logEvent('session_end', {
      'session_id': _sessionId,
      'duration_seconds': duration,
    });

    _sessionId = null;
    _sessionStartTime = null;
  }

  // ──────────────────────────────────────────────────────────────
  // Unified content interaction methods (GAFAM-aligned)
  // Use these for all new code. See 03-CONTEXT.md for rationale.
  // ──────────────────────────────────────────────────────────────

  /// Enregistre une interaction contenu unifiée (feed ou digest).
  /// Remplace les méthodes fragmentées (trackArticleRead, etc.)
  Future<void> trackContentInteraction({
    required String action, // read, save, dismiss, pass
    required String surface, // feed, digest
    required String contentId,
    required String sourceId,
    List<String> topics = const [],
    int? position,
    int timeSpentSeconds = 0,
  }) async {
    await _logEvent('content_interaction', {
      'session_id': _sessionId,
      'action': action,
      'surface': surface,
      'content_id': contentId,
      'source_id': sourceId,
      'topics': topics,
      'atomic_themes': null, // Forward-compatible for Camembert
      'position': position,
      'time_spent_seconds': timeSpentSeconds,
    });
  }

  /// Enregistre une session digest complète.
  Future<void> trackDigestSession({
    required String digestDate,
    required int articlesRead,
    required int articlesSaved,
    required int articlesDismissed,
    required int articlesPassed,
    required int totalTimeSeconds,
    required bool closureAchieved,
    required int streak,
  }) async {
    await _logEvent('digest_session', {
      'session_id': _sessionId,
      'digest_date': digestDate,
      'articles_read': articlesRead,
      'articles_saved': articlesSaved,
      'articles_dismissed': articlesDismissed,
      'articles_passed': articlesPassed,
      'total_time_seconds': totalTimeSeconds,
      'closure_achieved': closureAchieved,
      'streak': streak,
    });
  }

  /// Enregistre une session feed complète.
  Future<void> trackFeedSession({
    required double scrollDepthPercent,
    required int itemsViewed,
    required int itemsInteracted,
    required int totalTimeSeconds,
  }) async {
    await _logEvent('feed_session', {
      'session_id': _sessionId,
      'scroll_depth_percent': scrollDepthPercent,
      'items_viewed': itemsViewed,
      'items_interacted': itemsInteracted,
      'total_time_seconds': totalTimeSeconds,
    });
  }

  // ──────────────────────────────────────────────────────────────
  // Legacy methods — deprecated, use unified methods above
  // ──────────────────────────────────────────────────────────────

  /// @deprecated Use [trackContentInteraction] with action='read' instead.
  Future<void> trackArticleRead(
    String contentId,
    String sourceId,
    int timeSpentSeconds,
  ) async {
    await _logEvent('article_read', {
      'session_id': _sessionId,
      'content_id': contentId,
      'source_id': sourceId,
      'time_spent_seconds': timeSpentSeconds,
    });
  }

  /// @deprecated Use [trackFeedSession] instead.
  Future<void> trackFeedScroll(
    double scrollDepthPercent,
    int itemsViewed,
  ) async {
    await _logEvent('feed_scroll', {
      'session_id': _sessionId,
      'scroll_depth_percent': scrollDepthPercent,
      'items_viewed': itemsViewed,
    });
  }

  /// @deprecated Use [trackFeedSession] instead.
  Future<void> trackFeedComplete() async {
    await _logEvent('feed_complete', {'session_id': _sessionId});
  }

  Future<void> trackSourceAdd(String sourceId) async {
    await _logEvent('source_add', {'source_id': sourceId});
  }

  Future<void> trackSourceRemove(String sourceId) async {
    await _logEvent('source_remove', {'source_id': sourceId});
  }

  Future<void> trackAppFirstLaunch() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool('has_launched_before') == true) return;

    await _logEvent('app_first_launch', {});
    await prefs.setBool('has_launched_before', true);
  }

  Future<void> _logEvent(
    String eventType,
    Map<String, dynamic> eventData,
  ) async {
    try {
      if (_deviceId == null) await init();

      await _apiClient.dio.post(
        'analytics/events',
        data: {
          'event_type': eventType,
          'event_data': eventData,
          'device_id': _deviceId,
        },
      );
    } catch (e) {
      // Fail silently for analytics but log to console
      debugPrint('Analytics Error ($eventType): $e');
    }
  }
}
