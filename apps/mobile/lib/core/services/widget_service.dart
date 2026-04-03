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
class WidgetService {
  static const _androidName = 'FacteurWidget';

  /// Update the home screen widget with the latest digest and streak data.
  static Future<void> updateWidget({
    DigestResponse? digest,
    StreakModel? streak,
  }) async {
    try {
      // Extract first topic's first article
      final firstTopic = digest?.topics.firstOrNull;
      final firstArticle = firstTopic?.articles.firstOrNull;

      // Article data
      await HomeWidget.saveWidgetData(
        'article_title',
        firstArticle?.title ?? '',
      );
      await HomeWidget.saveWidgetData(
        'article_source',
        firstArticle?.source?.name ?? '',
      );
      await HomeWidget.saveWidgetData(
        'article_topic',
        firstTopic?.label ?? '',
      );

      // Download thumbnail locally for widget access
      if (firstArticle?.thumbnailUrl != null &&
          firstArticle!.thumbnailUrl!.isNotEmpty) {
        final imagePath = await _downloadImage(firstArticle.thumbnailUrl!);
        if (imagePath != null) {
          await HomeWidget.saveWidgetData('article_image_path', imagePath);
        }
      }

      // Digest status
      await HomeWidget.saveWidgetData(
        'digest_status',
        _computeStatus(digest),
      );
      await HomeWidget.saveWidgetData(
        'digest_progress',
        _computeProgress(digest),
      );
      await HomeWidget.saveWidgetData(
        'remaining_count',
        _computeRemaining(digest),
      );

      // Streak
      await HomeWidget.saveWidgetData(
        'streak',
        '${streak?.currentStreak ?? 0}',
      );

      // Trigger native widget refresh
      await HomeWidget.updateWidget(androidName: _androidName);
    } catch (e) {
      debugPrint('WidgetService: updateWidget failed: $e');
    }
  }

  static String _computeStatus(DigestResponse? digest) {
    if (digest == null) return 'none';
    if (digest.isCompleted) return 'completed';

    // Count processed items (read, saved, or dismissed)
    final total = _totalArticleCount(digest);
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

  static String _computeRemaining(DigestResponse? digest) {
    if (digest == null) return '0';
    // Total articles minus the 1 shown in the widget
    final totalArticles = digest.topics.fold<int>(
      0,
      (sum, topic) => sum + topic.articles.length,
    );
    final remaining = (totalArticles - 1).clamp(0, 99);
    return '$remaining';
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

  /// Request Android to pin the widget to the home screen.
  /// Shows the system dialog asking the user to confirm placement.
  static Future<void> requestPinWidget() async {
    try {
      await HomeWidget.requestPinWidget(
        androidName: _androidName,
      );
      debugPrint('WidgetService: requestPinWidget sent');
    } catch (e) {
      debugPrint('WidgetService: requestPinWidget failed: $e');
    }
  }

  /// Download an image to local storage and return the file path.
  static Future<String?> _downloadImage(String url) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final file = File('${dir.path}/widget_thumbnail.jpg');

      final dio = Dio();
      final response = await dio.get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );

      if (response.data != null) {
        await file.writeAsBytes(response.data!);
        return file.path;
      }
    } catch (e) {
      debugPrint('WidgetService: _downloadImage failed: $e');
    }
    return null;
  }
}
