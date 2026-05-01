import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:facteur/core/api/api_client.dart';
import 'package:facteur/core/api/notification_preferences_api_service.dart';
import 'package:facteur/core/services/posthog_service.dart';
import 'package:facteur/features/notifications/widgets/notification_activation_modal.dart';

class AnalyticsService {
  final ApiClient? _apiClient;
  final PostHogService? _posthog;
  String? _deviceId;
  String? _sessionId;
  DateTime? _sessionStartTime;

  AnalyticsService(ApiClient this._apiClient, {PostHogService? posthog})
      : _posthog = posthog;

  /// No-op constructor used when upstream deps (Supabase) aren't available
  /// — e.g. widget tests that don't initialize the app harness. Every
  /// `trackXxx` becomes a silent no-op.
  AnalyticsService.disabled()
      : _apiClient = null,
        _posthog = null;

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

  // ──────────────────────────────────────────────────────────────
  // Sprint 2 — feature-by-feature events (PR1)
  // ──────────────────────────────────────────────────────────────

  Future<void> trackDigestOpened({
    required String digestDate,
    int? itemsCount,
  }) async {
    final props = {
      'session_id': _sessionId,
      'digest_date': digestDate,
      'items_count': itemsCount,
    };
    await _logEvent('digest_opened', props);
    await _capturePostHog('digest_opened', props);
  }

  Future<void> trackDigestItemViewed({
    required String digestDate,
    required String contentId,
    required int position,
  }) async {
    final props = {
      'session_id': _sessionId,
      'digest_date': digestDate,
      'content_id': contentId,
      'position': position,
    };
    await _logEvent('digest_item_viewed', props);
  }

  Future<void> trackPerspectiveComparisonOpened({
    required String contentId,
    String? clusterId,
    int sourcesCount = 0,
  }) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'cluster_id': clusterId,
      'sources_count': sourcesCount,
    };
    await _logEvent('perspective_comparison_opened', props);
    await _capturePostHog('perspective_comparison_opened', props);
  }

  Future<void> trackPerspectiveArticleViewed({
    required String contentId,
    required String perspectiveArticleId,
    String? clusterId,
  }) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'perspective_article_id': perspectiveArticleId,
      'cluster_id': clusterId,
    };
    await _logEvent('perspective_article_viewed', props);
  }

  Future<void> trackPerspectiveComparisonClosed({
    required String contentId,
    String? clusterId,
    int viewedArticles = 0,
    int openedSeconds = 0,
  }) async {
    final props = {
      'session_id': _sessionId,
      'content_id': contentId,
      'cluster_id': clusterId,
      'viewed_articles': viewedArticles,
      'opened_seconds': openedSeconds,
    };
    await _logEvent('perspective_comparison_closed', props);
  }

  /// origin: 'digest' | 'feed' | 'settings'
  Future<void> trackArticleFeedbackSubmitted({
    required String contentId,
    required String feedbackType,
    required String origin,
    Map<String, dynamic> extra = const {},
  }) async {
    final props = <String, dynamic>{
      'session_id': _sessionId,
      'content_id': contentId,
      'feedback_type': feedbackType,
      'origin': origin,
      ...extra,
    };
    await _logEvent('article_feedback_submitted', props);
    await _capturePostHog('article_feedback_submitted', props);
  }

  /// origin: 'onboarding' | 'custom_topics'
  Future<void> trackSubtopicSuggestionShown({
    required String subtopicSlug,
    required String origin,
  }) async {
    await _logEvent('subtopic_suggestion_shown', {
      'session_id': _sessionId,
      'subtopic_slug': subtopicSlug,
      'origin': origin,
    });
  }

  Future<void> trackSubtopicAdded({
    required String subtopicSlug,
    required String origin,
  }) async {
    final props = {
      'session_id': _sessionId,
      'subtopic_slug': subtopicSlug,
      'origin': origin,
    };
    await _logEvent('subtopic_added', props);
    await _capturePostHog('subtopic_added', props);
  }

  Future<void> trackSubtopicRemoved({
    required String subtopicSlug,
    required String origin,
  }) async {
    await _logEvent('subtopic_removed', {
      'session_id': _sessionId,
      'subtopic_slug': subtopicSlug,
      'origin': origin,
    });
  }

  /// Generic settings/preference toggle. `key` is a stable snake_case identifier
  /// (e.g. 'notifications_daily_digest'), oldValue/newValue are coerced to string
  /// to keep the event payload shape uniform across bool/int/string toggles.
  Future<void> trackPreferenceChanged({
    required String key,
    required Object? oldValue,
    required Object? newValue,
  }) async {
    final props = {
      'session_id': _sessionId,
      'key': key,
      'old_value': oldValue?.toString(),
      'new_value': newValue?.toString(),
    };
    await _logEvent('preference_changed', props);
    await _capturePostHog('preference_changed', props);
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

  Future<void> trackAddSourceContentTypeFilter(String contentType) async {
    await _logEvent(
      'add_source_content_type_filter',
      {'content_type': contentType},
    );
  }

  Future<void> trackAddSourceExpand(String query) async {
    await _logEvent('add_source_expand', {'query': query});
  }

  // ──────────────────────────────────────────────────────────────
  // Story 14.3 — Self-reported "well-informed" score (1-10 NPS).
  // Trois events pour construire le funnel shown → skipped / submitted.
  // ──────────────────────────────────────────────────────────────

  Future<void> trackWellInformedPromptShown({
    String context = 'digest_inline',
  }) async {
    final props = {
      'session_id': _sessionId,
      'context': context,
    };
    await _logEvent('well_informed_prompt_shown', props);
  }

  Future<void> trackWellInformedPromptSkipped({
    String context = 'digest_inline',
  }) async {
    final props = {
      'session_id': _sessionId,
      'context': context,
    };
    await _logEvent('well_informed_prompt_skipped', props);
    await _capturePostHog('well_informed_prompt_skipped', props);
  }

  Future<void> trackWellInformedScoreSubmitted({
    required int score,
    String context = 'digest_inline',
  }) async {
    final props = {
      'session_id': _sessionId,
      'score': score,
      'context': context,
    };
    await _logEvent('well_informed_score_submitted', props);
    await _capturePostHog('well_informed_score_submitted', props);
  }

  // ──────────────────────────────────────────────────────────────
  // Home-screen widget — refonte instrumentation
  // ──────────────────────────────────────────────────────────────

  Future<void> trackWidgetPinNudgeShown() async {
    final props = {'session_id': _sessionId};
    await _logEvent('widget_pin_nudge_shown', props);
    await _capturePostHog('widget_pin_nudge_shown', props);
  }

  Future<void> trackWidgetPinRequested() async {
    final props = {'session_id': _sessionId};
    await _logEvent('widget_pin_requested', props);
    await _capturePostHog('widget_pin_requested', props);
  }

  Future<void> trackWidgetPinDismissed() async {
    final props = {'session_id': _sessionId};
    await _logEvent('widget_pin_dismissed', props);
    await _capturePostHog('widget_pin_dismissed', props);
  }

  Future<void> trackDiscoverDisableStepShown() async {
    final props = {'session_id': _sessionId};
    await _logEvent('discover_disable_step_shown', props);
    await _capturePostHog('discover_disable_step_shown', props);
  }

  Future<void> trackDiscoverDisableConfirmed() async {
    final props = {'session_id': _sessionId};
    await _logEvent('discover_disable_confirmed', props);
    await _capturePostHog('discover_disable_confirmed', props);
  }

  Future<void> trackDiscoverDisableSkipped() async {
    final props = {'session_id': _sessionId};
    await _logEvent('discover_disable_skipped', props);
    await _capturePostHog('discover_disable_skipped', props);
  }

  /// target: 'digest' | 'article' | 'feed'.
  /// Fired whenever a `io.supabase.facteur://` widget URI lands in the app.
  Future<void> trackWidgetAppOpened({
    required String target,
    String? articleId,
    int? position,
    String? topicId,
  }) async {
    final props = <String, dynamic>{
      'session_id': _sessionId,
      'target': target,
      'article_id': articleId,
      'position': position,
      'topic_id': topicId,
    };
    await _logEvent('widget_app_opened', props);
    await _capturePostHog('widget_app_opened', props);
  }

  /// Fired when the widget URI specifically asked for an article reader,
  /// to power the widget→reader CTR funnel without mixing with `digest`/`feed`
  /// taps.
  Future<void> trackWidgetArticleOpened({
    required String articleId,
    int? position,
    String? topicId,
  }) async {
    final props = <String, dynamic>{
      'session_id': _sessionId,
      'article_id': articleId,
      'position': position,
      'topic_id': topicId,
    };
    await _logEvent('widget_article_opened', props);
    await _capturePostHog('widget_article_opened', props);
  }

  // ── Notifications activation events (brief §7) ──────────────────────

  Future<void> trackModalNotifShown({required ActivationTrigger trigger}) async {
    final props = <String, dynamic>{'trigger': trigger.name};
    await _logEvent('modal_notif_shown', props);
    await _capturePostHog('modal_notif_shown', props);
  }

  Future<void> trackModalNotifPresetChanged({required NotifPreset preset}) async {
    final props = <String, dynamic>{'preset': preset.wire};
    await _logEvent('modal_notif_preset_changed', props);
    await _capturePostHog('modal_notif_preset_changed', props);
  }

  Future<void> trackModalNotifTimeChanged({required NotifTimeSlot timeSlot}) async {
    final props = <String, dynamic>{'time': timeSlot.wire};
    await _logEvent('modal_notif_time_changed', props);
    await _capturePostHog('modal_notif_time_changed', props);
  }

  Future<void> trackModalNotifConfirmed({
    required NotifPreset preset,
    required NotifTimeSlot timeSlot,
    required bool osPermissionGranted,
  }) async {
    final props = <String, dynamic>{
      'preset': preset.wire,
      'time': timeSlot.wire,
      'os_permission_granted': osPermissionGranted,
    };
    await _logEvent('modal_notif_confirmed', props);
    await _capturePostHog('modal_notif_confirmed', props);
  }

  Future<void> trackModalNotifDismissed() async {
    await _logEvent('modal_notif_dismissed', {});
    await _capturePostHog('modal_notif_dismissed', {});
  }

  Future<void> trackRenudgeShown({required int displayCount}) async {
    final props = <String, dynamic>{'display_count': displayCount};
    await _logEvent('renudge_shown', props);
    await _capturePostHog('renudge_shown', props);
  }

  Future<void> trackRenudgeConfirmed() async {
    await _logEvent('renudge_confirmed', {});
    await _capturePostHog('renudge_confirmed', {});
  }

  Future<void> trackRenudgeDismissed() async {
    await _logEvent('renudge_dismissed', {});
    await _capturePostHog('renudge_dismissed', {});
  }

  Future<void> trackNotifScheduled({
    required String type, // daily_a / daily_b / daily_empty / community
    required String time,
  }) async {
    final props = <String, dynamic>{'type': type, 'time': time};
    await _logEvent('notif_scheduled', props);
    await _capturePostHog('notif_scheduled', props);
  }

  Future<void> trackNotifOpened({
    required String type,
    int? timeToOpenSeconds,
  }) async {
    final props = <String, dynamic>{
      'type': type,
      'time_to_open': timeToOpenSeconds,
    };
    await _logEvent('notif_opened', props);
    await _capturePostHog('notif_opened', props);
  }

  Future<void> trackNotifSettingsChanged({
    required NotifPreset fromPreset,
    required NotifPreset toPreset,
  }) async {
    final props = <String, dynamic>{
      'from_preset': fromPreset.wire,
      'to_preset': toPreset.wire,
    };
    await _logEvent('notif_settings_changed', props);
    await _capturePostHog('notif_settings_changed', props);
  }

  Future<void> trackNotifDisabled({required String source}) async {
    // source: 'in_app' or 'os_settings'
    final props = <String, dynamic>{'source': source};
    await _logEvent('notif_disabled', props);
    await _capturePostHog('notif_disabled', props);
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
    final client = _apiClient;
    if (client == null) return;
    try {
      if (_deviceId == null) await init();

      await client.dio.post(
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
