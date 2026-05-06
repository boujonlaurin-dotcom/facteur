import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:home_widget/home_widget.dart';
import 'package:path_provider/path_provider.dart';
import 'package:dio/dio.dart';

import '../../config/topic_labels.dart';
import '../../features/digest/models/digest_models.dart';
import '../../features/feed/models/content_model.dart';
import '../../features/gamification/models/streak_model.dart';

/// Service to push digest data to the Android home screen widget.
///
/// Data flows: Flutter → SharedPreferences (via home_widget) → FacteurWidget.kt
///
/// Schema:
/// - `articles_json` : Essentiel — JSON array of up to 5 articles
/// - `feed_articles_json` : Flux — JSON array of up to 30 feed items
/// - `articles_updated_at` : epoch millis of last successful refresh
/// - `digest_status` : 'none' | 'available' | 'in_progress' | 'completed'
/// - `digest_progress` : 'X/Y'
/// - `streak` : current streak as string
/// - `widget_mode` : 'essentiel' | 'flux' (written natively at tab tap)
class WidgetService {
  static const _androidName = 'FacteurWidget';
  static const _maxArticles = 5;
  static const _maxFeedArticles = 30;
  // Cap thumbnails to keep RemoteViews IPC under Binder's ~1 MB ceiling.
  static const _maxFeedThumbnails = 10;
  static final _dio = Dio();

  /// Update the home screen widget with the latest digest, feed and/or streak.
  /// Each parameter is independent — passing only one preserves the others.
  static Future<void> updateWidget({
    DigestResponse? digest,
    List<Content>? feedItems,
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

      if (feedItems != null) {
        final items = await _buildFeedArticleList(feedItems);
        await HomeWidget.saveWidgetData(
          'feed_articles_json',
          jsonEncode(items),
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
      await HomeWidget.saveWidgetData('feed_articles_json', '[]');
      await HomeWidget.saveWidgetData('articles_updated_at', '0');
      await HomeWidget.saveWidgetData('digest_status', 'none');
      await HomeWidget.saveWidgetData('digest_progress', '0/0');
      await HomeWidget.saveWidgetData('streak', '0');
      await HomeWidget.saveWidgetData('widget_mode', 'essentiel');
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
  // Feed (Flux) serialization
  // ──────────────────────────────────────────────────────────────

  /// Build the Flux article list (max 30) from the current feed state.
  /// Thumbnails only downloaded for the first [_maxFeedThumbnails] entries
  /// to keep the RemoteViews IPC payload under Binder's ~1 MB ceiling.
  static Future<List<Map<String, dynamic>>> _buildFeedArticleList(
    List<Content> items,
  ) async {
    if (items.isEmpty) return const [];
    final capped = items.take(_maxFeedArticles).toList(growable: false);
    return Future.wait([
      for (var i = 0; i < capped.length; i++)
        _serializeFeedItem(
          item: capped[i],
          rank: i + 1,
          downloadThumbnail: i < _maxFeedThumbnails,
        ),
    ]);
  }

  static Future<Map<String, dynamic>> _serializeFeedItem({
    required Content item,
    required int rank,
    required bool downloadThumbnail,
  }) async {
    final downloads = await Future.wait([
      downloadThumbnail
          ? _downloadIfPresent(
              item.thumbnailUrl,
              'widget_feed_thumbnail_$rank.jpg',
            )
          : Future<String?>.value(null),
      _downloadIfPresent(
        item.source.logoUrl,
        'widget_feed_logo_$rank.png',
      ),
    ]);
    final thumbPath = downloads[0];
    final logoPath = downloads[1];

    final topicSlug = item.topics.isNotEmpty ? item.topics.first : '';
    final topicLabel = topicSlugToLabel[topicSlug] ?? '';

    return {
      'id': item.id,
      'rank': rank,
      'topic_id': topicSlug,
      'topic_label': topicLabel,
      'is_main': false,
      'title': item.title,
      'source_name': item.source.name,
      'source_logo_path': logoPath ?? '',
      'thumbnail_path': thumbPath ?? '',
      'perspective_count': 0,
      'published_at_iso': item.publishedAt.toUtc().toIso8601String(),
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
