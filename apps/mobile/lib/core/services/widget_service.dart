import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../../features/digest/models/digest_models.dart';
import '../../features/gamification/models/streak_model.dart';

/// Service to push digest data to the Android home screen widget.
///
/// Data flows: Flutter → SharedPreferences (via home_widget) → FacteurWidget.kt
///
/// Schema (since refonte v2):
/// - `articles_json` : JSON array of up to 5 articles (see [_serializeArticle])
/// - `articles_updated_at` : epoch millis of last successful refresh
/// - `digest_status` : 'none' | 'available' | 'in_progress' | 'completed'
/// - `digest_progress` : 'X/Y'
/// - `streak` : current streak as string
class WidgetService {
  static const _androidName = 'FacteurWidget';
  static const _maxArticles = 5;
  static final _dio = Dio();

  /// Update the home screen widget with the latest digest and/or streak data.
  ///
  /// Each parameter is independent: passing only `streak` will refresh the
  /// streak counter without touching `articles_json`. This avoids wiping
  /// previously saved articles when streak refresh fires after digest fetch.
  static Future<void> updateWidget({
    DigestResponse? digest,
    StreakModel? streak,
  }) async {
    try {
      if (digest != null) {
        final articles = await _buildArticleList(digest);
        await HomeWidget.saveWidgetData(
          'articles_json',
          jsonEncode(articles),
        );
        await HomeWidget.saveWidgetData(
          'articles_updated_at',
          '${DateTime.now().millisecondsSinceEpoch}',
        );
        await HomeWidget.saveWidgetData(
          'digest_status',
          _computeStatus(digest),
        );
        await HomeWidget.saveWidgetData(
          'digest_progress',
          _computeProgress(digest),
        );
      }

      if (streak != null) {
        await HomeWidget.saveWidgetData('streak', '${streak.currentStreak}');
      }

      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (e) {
      debugPrint('WidgetService: updateWidget failed: $e');
    }
  }

  /// Push a placeholder payload when no digest is available yet (cold install,
  /// pre-first-fetch). Idempotent — checked via SharedPreferences.
  static Future<void> initWidgetIfNeeded() async {
    try {
      final existing = await HomeWidget.getWidgetData<String>('articles_json');
      if (existing != null && existing.isNotEmpty && existing != '[]') {
        return;
      }
      await HomeWidget.saveWidgetData('articles_json', jsonEncode(<dynamic>[]));
      await HomeWidget.saveWidgetData('digest_status', 'none');
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (e) {
      debugPrint('WidgetService: initWidgetIfNeeded failed: $e');
    }
  }

  /// Wipe widget data on logout so the next user never briefly sees the
  /// previous account's digest on their home screen.
  static Future<void> clear() async {
    try {
      await HomeWidget.saveWidgetData('articles_json', '[]');
      await HomeWidget.saveWidgetData('articles_updated_at', '0');
      await HomeWidget.saveWidgetData('digest_status', 'none');
      await HomeWidget.saveWidgetData('digest_progress', '0/0');
      await HomeWidget.saveWidgetData('streak', '0');
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (e) {
      debugPrint('WidgetService: clear failed: $e');
    }
  }

  /// Request Android to pin the widget to the home screen.
  static Future<void> requestPinWidget() async {
    try {
      await HomeWidget.requestPinWidget(androidName: _androidName);
    } catch (e) {
      debugPrint('WidgetService: requestPinWidget failed: $e');
    }
  }

  // ──────────────────────────────────────────────────────────────
  // Article serialization
  // ──────────────────────────────────────────────────────────────

  /// Build the list of widget articles (max 5) from a digest response.
  ///
  /// Strategy mirrors `topic_section.dart` `_pickSingleton`:
  ///  - Iterate topics in rank order, take 1 article per topic
  ///  - Prefer a followed-source article when available
  ///  - Topic 1 article gets `is_main = true` (drives "À la Une" badge)
  static Future<List<Map<String, dynamic>>> _buildArticleList(
    DigestResponse? digest,
  ) async {
    if (digest == null || digest.topics.isEmpty) return const [];

    final result = <Map<String, dynamic>>[];
    var rank = 1;
    for (final topic in digest.topics) {
      if (result.length >= _maxArticles) break;
      if (topic.articles.isEmpty) continue;
      final article = _pickSingleton(topic);
      if (article.isDismissed) continue;
      result.add(await _serializeArticle(
        article: article,
        topic: topic,
        rank: rank,
        isMain: rank == 1,
      ));
      rank++;
    }
    return result;
  }

  static DigestItem _pickSingleton(DigestTopic topic) {
    for (final a in topic.articles) {
      if (a.isFollowedSource) return a;
    }
    return topic.articles.first;
  }

  static Future<Map<String, dynamic>> _serializeArticle({
    required DigestItem article,
    required DigestTopic topic,
    required int rank,
    required bool isMain,
  }) async {
    final thumbPath = await _downloadIfPresent(
      article.thumbnailUrl,
      'widget_thumbnail_$rank.jpg',
    );
    final logoPath = await _downloadIfPresent(
      article.source?.logoUrl,
      'widget_logo_$rank.png',
    );

    return {
      'id': article.contentId,
      'rank': rank,
      'topic_id': topic.topicId,
      'topic_label': topic.label,
      'is_main': isMain,
      'title': article.title,
      'source_name': article.source?.name ?? '',
      'source_logo_path': logoPath ?? '',
      'thumbnail_path': thumbPath ?? '',
      'perspective_count': topic.perspectiveCount,
      'published_at_iso': article.publishedAt?.toUtc().toIso8601String() ?? '',
    };
  }

  // ──────────────────────────────────────────────────────────────
  // Status helpers (kept stable for backward-compat header)
  // ──────────────────────────────────────────────────────────────

  static String _computeStatus(DigestResponse? digest) {
    if (digest == null) return 'none';
    if (digest.isCompleted) return 'completed';
    final processed = _processedArticleCount(digest);
    if (processed > 0) return 'in_progress';
    return 'available';
  }

  static String _computeProgress(DigestResponse? digest) {
    if (digest == null) return '0/0';
    final total = _totalArticleCount(digest);
    final processed = _processedArticleCount(digest);
    return '$processed/$total';
  }

  static int _totalArticleCount(DigestResponse digest) {
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

  static int _processedArticleCount(DigestResponse digest) {
    if (digest.usesTopics) {
      var count = digest.topics.where((t) => t.isCovered).length;
      if (digest.usesEditorial) {
        final p = digest.pepite;
        if (p != null && (p.isRead || p.isSaved || p.isDismissed)) count++;
        final c = digest.coupDeCoeur;
        if (c != null && (c.isRead || c.isSaved || c.isDismissed)) count++;
      }
      return count;
    }
    return digest.items
        .where((i) => i.isRead || i.isDismissed || i.isSaved)
        .length;
  }

  /// Download an image to local storage and return the file path.
  static Future<String?> _downloadIfPresent(
    String? url,
    String filename,
  ) async {
    if (url == null || url.isEmpty) return null;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/$filename');
      final response = await _dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      if (response.data != null) {
        await file.writeAsBytes(response.data!);
        return file.path;
      }
    } catch (e) {
      debugPrint('WidgetService: download failed ($url): $e');
    }
    return null;
  }
}
