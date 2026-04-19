import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/services/posthog_service.dart';

class AnalyticsService {
  final ApiClient _apiClient;
  final PostHogService? _posthog;
  String? _deviceId;
  String? _sessionId;
  DateTime? _sessionStartTime;

  AnalyticsService(this._apiClient, {PostHogService? posthog})
      : _posthog = posthog;

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
    // Story 14.1 — PostHog uses `app_open` as the conventional event name
    // for DAU/retention computation. We mirror session_start to it.
    await _capturePostHog('app_open', {
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
    final props = {
      'session_id': _sessionId,
      'action': action,
      'surface': surface,
      'content_id': contentId,
      'source_id': sourceId,
      'topics': topics,
      'atomic_themes': null, // Forward-compatible for Camembert
      'position': position,
      'time_spent_seconds': timeSpentSeconds,
    };
    await _logEvent('content_interaction', props);

    // Story 14.1 — dedicated PostHog events for clean funnel/retention.
    if (action == 'read') {
      await _capturePostHog('article_read', props);
      // Threshold ≥ 30 s signals a completed article (conventional for
      // text content; videos/podcasts already have dedicated completion
      // events in their own flows).
      if (timeSpentSeconds >= 30) {
        await _capturePostHog('article_completed', props);
      }
    }
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
    final props = {
      'session_id': _sessionId,
      'digest_date': digestDate,
      'articles_read': articlesRead,
      'articles_saved': articlesSaved,
      'articles_dismissed': articlesDismissed,
      'articles_passed': articlesPassed,
      'total_time_seconds': totalTimeSeconds,
      'closure_achieved': closureAchieved,
      'streak': streak,
    };
    await _logEvent('digest_session', props);
    await _capturePostHog('digest_session', props);
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

  /// Track the Ground News comparison screen open (H2 signal, Story 14.1).
  Future<void> trackComparisonViewed({
    required String clusterId,
    int sourcesCount = 0,
  }) async {
    final props = {
      'session_id': _sessionId,
      'cluster_id': clusterId,
      'sources_count': sourcesCount,
    };
    await _logEvent('comparison_viewed', props);
    await _capturePostHog('comparison_viewed', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Legacy methods — deprecated, use unified methods above
  // ──────────────────────────────────────────────────────────────

  /// @deprecated Use [trackContentInteraction] with action='read' instead.
  ///
  /// Story 14.1 — even though this is deprecated, it's still the only call
  /// site for feed/detail reading flows (which carry real `timeSpentSeconds`).
  /// We MUST mirror to PostHog from here too, otherwise `article_read` and
  /// `article_completed` PostHog events would never fire from the surfaces
  /// where users actually spend reading time. The digest "save" flow that
  /// uses `trackContentInteraction` hardcodes `timeSpentSeconds: 0`.
  Future<void> trackArticleRead(
    String contentId,
    String sourceId,
    int timeSpentSeconds,
  ) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'source_id': sourceId,
      'time_spent_seconds': timeSpentSeconds,
    };
    await _logEvent('article_read', props);

    await _capturePostHog('article_read', props);
    if (timeSpentSeconds >= 30) {
      await _capturePostHog('article_completed', props);
    }
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
    await _capturePostHog('source_added', {'source_id': sourceId});
  }

  Future<void> trackSourceRemove(String sourceId) async {
    await _logEvent('source_remove', {'source_id': sourceId});
  }


  Future<void> trackAddSourceThemeTap(String themeSlug) async {
    await _logEvent('add_source_theme_tap', {'theme_slug': themeSlug});
  }

  Future<void> trackAddSourceExampleTap(String exampleText) async {
    await _logEvent('add_source_example_tap', {'example_text': exampleText});
  }

  Future<void> trackAddSourceGemTap(String sourceId) async {
    await _logEvent('add_source_gem_tap', {'source_id': sourceId});
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

  /// Push un event vers PostHog — fire-and-forget, silencieux si désactivé.
  /// PostHog requiert des propriétés `Object` (pas nullable) donc on filtre.
  Future<void> _capturePostHog(
    String event,
    Map<String, dynamic> rawProps,
  ) async {
    final ph = _posthog;
    if (ph == null || !ph.isEnabled) return;
    final cleanProps = <String, Object>{};
    rawProps.forEach((key, value) {
      if (value != null) cleanProps[key] = value as Object;
    });
    await ph.capture(event: event, properties: cleanProps);
  }
}
