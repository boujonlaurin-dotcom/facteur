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
        '/analytics/events',
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
