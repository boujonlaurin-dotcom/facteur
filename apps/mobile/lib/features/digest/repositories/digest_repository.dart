import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';

/// Repository for digest-related API operations
class DigestRepository {
  final ApiClient _apiClient;

  DigestRepository(this._apiClient);

  /// Get or create today's digest for the current user
  Future<DigestResponse> getDigest({DateTime? targetDate}) async {
    try {
      final queryParams = <String, dynamic>{};
      if (targetDate != null) {
        queryParams['target_date'] = targetDate.toIso8601String().split('T')[0];
      }

      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/digest',
        queryParameters: queryParams.isNotEmpty ? queryParams : null,
      );

      if (response.statusCode == 200 && response.data != null) {
        return DigestResponse.fromJson(response.data!);
      }
      throw Exception('Failed to load digest: ${response.statusCode}');
    } catch (e) {
      print('DigestRepository: [ERROR] getDigest: $e');
      rethrow;
    }
  }

  /// Get a digest by its ID
  Future<DigestResponse> getDigestById(String digestId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        '/api/digest/$digestId',
      );

      if (response.statusCode == 200 && response.data != null) {
        return DigestResponse.fromJson(response.data!);
      }
      throw Exception('Failed to load digest: ${response.statusCode}');
    } catch (e) {
      print('DigestRepository: [ERROR] getDigestById: $e');
      rethrow;
    }
  }

  /// Apply an action (read, save, not_interested, undo) to a digest item
  Future<DigestActionResponse> applyAction({
    required String digestId,
    required String contentId,
    required String action, // 'read', 'save', 'not_interested', 'undo'
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/digest/$digestId/action',
        data: {
          'content_id': contentId,
          'action': action,
        },
      );

      if (response.statusCode == 200 && response.data != null) {
        return DigestActionResponse.fromJson(response.data!);
      }
      throw Exception('Failed to apply action: ${response.statusCode}');
    } on DioException catch (e) {
      print('DigestRepository: [ERROR] applyAction DioException: ${e.message}');
      if (e.response?.data != null) {
        throw Exception('API Error: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      print('DigestRepository: [ERROR] applyAction: $e');
      rethrow;
    }
  }

  /// Complete a digest (mark as finished)
  Future<DigestCompletionResponse> completeDigest(String digestId) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        '/api/digest/$digestId/complete',
      );

      if (response.statusCode == 200 && response.data != null) {
        return DigestCompletionResponse.fromJson(response.data!);
      }
      throw Exception('Failed to complete digest: ${response.statusCode}');
    } on DioException catch (e) {
      print(
          'DigestRepository: [ERROR] completeDigest DioException: ${e.message}');
      if (e.response?.data != null) {
        throw Exception('API Error: ${e.response?.data}');
      }
      rethrow;
    } catch (e) {
      print('DigestRepository: [ERROR] completeDigest: $e');
      rethrow;
    }
  }
}

/// Response model for digest data
class DigestResponse {
  final String digestId;
  final String userId;
  final DateTime targetDate;
  final DateTime generatedAt;
  final List<DigestItem> items;
  final bool isCompleted;
  final DateTime? completedAt;

  DigestResponse({
    required this.digestId,
    required this.userId,
    required this.targetDate,
    required this.generatedAt,
    required this.items,
    required this.isCompleted,
    this.completedAt,
  });

  factory DigestResponse.fromJson(Map<String, dynamic> json) {
    final itemsList = (json['items'] as List<dynamic>?)
            ?.whereType<Map<String, dynamic>>()
            .map((e) => DigestItem.fromJson(e))
            .toList() ??
        [];

    return DigestResponse(
      digestId: (json['digest_id'] as String?) ?? '',
      userId: (json['user_id'] as String?) ?? '',
      targetDate: _parseDateTime(json['target_date']) ?? DateTime.now(),
      generatedAt: _parseDateTime(json['generated_at']) ?? DateTime.now(),
      items: itemsList,
      isCompleted: (json['is_completed'] as bool?) ?? false,
      completedAt: _parseDateTime(json['completed_at']),
    );
  }
}

/// Individual digest item (article)
class DigestItem {
  final String contentId;
  final String title;
  final String url;
  final String? thumbnailUrl;
  final String? description;
  final ContentType contentType;
  final int? durationSeconds;
  final DateTime publishedAt;
  final SourceMini source;
  final int rank;
  final String reason;
  final bool isRead;
  final bool isSaved;
  final bool isDismissed;

  DigestItem({
    required this.contentId,
    required this.title,
    required this.url,
    this.thumbnailUrl,
    this.description,
    required this.contentType,
    this.durationSeconds,
    required this.publishedAt,
    required this.source,
    required this.rank,
    required this.reason,
    this.isRead = false,
    this.isSaved = false,
    this.isDismissed = false,
  });

  factory DigestItem.fromJson(Map<String, dynamic> json) {
    return DigestItem(
      contentId: (json['content_id'] as String?) ?? '',
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      thumbnailUrl: json['thumbnail_url'] as String?,
      description: json['description'] as String?,
      contentType: _parseContentType(json['content_type']),
      durationSeconds: (json['duration_seconds'] as num?)?.toInt(),
      publishedAt: _parseDateTime(json['published_at']) ?? DateTime.now(),
      source:
          SourceMini.fromJson((json['source'] as Map<String, dynamic>?) ?? {}),
      rank: (json['rank'] as num?)?.toInt() ?? 0,
      reason: (json['reason'] as String?) ?? '',
      isRead: (json['is_read'] as bool?) ?? false,
      isSaved: (json['is_saved'] as bool?) ?? false,
      isDismissed: (json['is_dismissed'] as bool?) ?? false,
    );
  }

  /// Create a copy with updated action states
  DigestItem copyWith({
    bool? isRead,
    bool? isSaved,
    bool? isDismissed,
  }) {
    return DigestItem(
      contentId: contentId,
      title: title,
      url: url,
      thumbnailUrl: thumbnailUrl,
      description: description,
      contentType: contentType,
      durationSeconds: durationSeconds,
      publishedAt: publishedAt,
      source: source,
      rank: rank,
      reason: reason,
      isRead: isRead ?? this.isRead,
      isSaved: isSaved ?? this.isSaved,
      isDismissed: isDismissed ?? this.isDismissed,
    );
  }
}

/// Mini source model for digest items
class SourceMini {
  final String id;
  final String name;
  final String? logoUrl;
  final String? theme;

  SourceMini({
    required this.id,
    required this.name,
    this.logoUrl,
    this.theme,
  });

  factory SourceMini.fromJson(Map<String, dynamic> json) {
    return SourceMini(
      id: (json['id'] as String?) ?? '',
      name: (json['name'] as String?) ?? '',
      logoUrl: json['logo_url'] as String?,
      theme: json['theme'] as String?,
    );
  }
}

/// Content type enum
enum ContentType {
  article,
  video,
  audio,
  youtube,
}

ContentType _parseContentType(dynamic value) {
  if (value == null) return ContentType.article;
  final str = value.toString().toLowerCase();
  switch (str) {
    case 'video':
      return ContentType.video;
    case 'audio':
      return ContentType.audio;
    case 'youtube':
      return ContentType.youtube;
    case 'article':
    default:
      return ContentType.article;
  }
}

DateTime? _parseDateTime(dynamic value) {
  if (value == null) return null;
  if (value is String) {
    try {
      return DateTime.parse(value);
    } catch (_) {
      return null;
    }
  }
  return null;
}

/// Response from action endpoint
class DigestActionResponse {
  final bool success;
  final String contentId;
  final String action;
  final DateTime appliedAt;
  final String message;

  DigestActionResponse({
    required this.success,
    required this.contentId,
    required this.action,
    required this.appliedAt,
    required this.message,
  });

  factory DigestActionResponse.fromJson(Map<String, dynamic> json) {
    return DigestActionResponse(
      success: (json['success'] as bool?) ?? false,
      contentId: (json['content_id'] as String?) ?? '',
      action: (json['action'] as String?) ?? '',
      appliedAt: _parseDateTime(json['applied_at']) ?? DateTime.now(),
      message: (json['message'] as String?) ?? '',
    );
  }
}

/// Response from completion endpoint
class DigestCompletionResponse {
  final bool success;
  final String digestId;
  final DateTime completedAt;
  final int articlesRead;
  final int articlesSaved;
  final int articlesDismissed;
  final int closureTimeSeconds;
  final int closureStreak;
  final String? streakMessage;

  DigestCompletionResponse({
    required this.success,
    required this.digestId,
    required this.completedAt,
    required this.articlesRead,
    required this.articlesSaved,
    required this.articlesDismissed,
    required this.closureTimeSeconds,
    required this.closureStreak,
    this.streakMessage,
  });

  factory DigestCompletionResponse.fromJson(Map<String, dynamic> json) {
    return DigestCompletionResponse(
      success: (json['success'] as bool?) ?? false,
      digestId: (json['digest_id'] as String?) ?? '',
      completedAt: _parseDateTime(json['completed_at']) ?? DateTime.now(),
      articlesRead: (json['articles_read'] as num?)?.toInt() ?? 0,
      articlesSaved: (json['articles_saved'] as num?)?.toInt() ?? 0,
      articlesDismissed: (json['articles_dismissed'] as num?)?.toInt() ?? 0,
      closureTimeSeconds: (json['closure_time_seconds'] as num?)?.toInt() ?? 0,
      closureStreak: (json['closure_streak'] as num?)?.toInt() ?? 0,
      streakMessage: json['streak_message'] as String?,
    );
  }
}
