import 'package:dio/dio.dart';
import '../../../core/api/api_client.dart';
import '../models/content_model.dart';

class FeedRepository {
  final ApiClient _apiClient;

  FeedRepository(this._apiClient);

  Future<FeedResponse> getFeed({
    int page = 1,
    int limit = 20,
    String? contentType,
    bool savedOnly = false,
    String? mode,
  }) async {
    try {
      // Le backend renvoie directement une List<dynamic> pour le moment
      // et non une enveloppe { items: [], pagination: {} }
      final offset = (page - 1) * limit;

      final queryParams = <String, dynamic>{
        'limit': limit,
        'offset': offset,
      };

      if (contentType != null) {
        queryParams['type'] = contentType;
      }

      if (savedOnly) {
        queryParams['saved'] = true;
      }

      if (mode != null) {
        queryParams['mode'] = mode;
      }

      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'feed/', // Trailing slash to avoid 307 redirect which strips auth header
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data == null) {
          return FeedResponse(
            items: [],
            briefing: [],
            pagination: Pagination(
                page: page, perPage: limit, total: 0, hasNext: false),
          );
        }

        // Le backend (M5) ne renvoie pas de pagination explicite,
        // on utilise FeedResponse.fromJson qui parse 'items' et 'briefing'.
        // Mais 'pagination' sera par défaut (hasNext: false).
        // On doit donc injecter hasNext manuellement ou reconstruire l'objet.

        // Option simple: parser manuellement ici pour garder la logique hasNext
        final itemsList = (data['items'] as List?)
                ?.map((e) => Content.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];

        final briefingList = (data['briefing'] as List?)
                ?.map((e) => DailyTop3Item.fromJson(e as Map<String, dynamic>))
                .toList() ??
            [];

        // On infère la pagination car le backend ne donne pas de métadonnées
        // Si on a reçu 'limit' items, on suppose qu'il y a une page suivante
        final hasNext = itemsList.length >= limit;

        return FeedResponse(
          items: itemsList,
          briefing: briefingList,
          pagination: Pagination(
            page: page,
            perPage: limit,
            total: 0, // Inconnu
            hasNext: hasNext,
          ),
        );
      }
      throw Exception('Failed to load feed: ${response.statusCode}');
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] getFeed: $e');
      rethrow;
    }
  }

  Future<void> markBriefingAsRead(String contentId) async {
    await _apiClient.dio.post('/feed/briefing/$contentId/read');
  }

  Future<Content?> getContent(String contentId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'contents/$contentId',
      );

      if (response.statusCode == 200 && response.data != null) {
        return Content.fromJson(response.data!);
      }
      return null;
    } catch (e) {
      print('FeedRepository: [ERROR] getContent: $e');
      return null;
    }
  }

  Future<void> toggleSave(String contentId, bool isSaved) async {
    try {
      if (isSaved) {
        await _apiClient.dio.post<void>('contents/$contentId/save');
      } else {
        await _apiClient.dio.delete<void>('contents/$contentId/save');
      }
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] toggleSave: $e');
      rethrow;
    }
  }

  Future<void> hideContent(String contentId, HiddenReason reason) async {
    try {
      await _apiClient.dio.post<void>(
        'contents/$contentId/hide',
        data: {'reason': reason.name},
      );
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] hideContent: $e');
      rethrow;
    }
  }

  Future<void> updateContentStatus(
      String contentId, ContentStatus status) async {
    try {
      await _apiClient.dio.post<void>(
        'contents/$contentId/status',
        data: {'status': status.name},
      );
    } catch (e) {
      // ignore: avoid_print
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      print('🔴 FEED REPOSITORY ERROR: updateContentStatus');
      print('ID: $contentId');
      if (e is DioException) {
        print('STATUS: ${e.response?.statusCode}');
        print('DATA: ${e.response?.data}');
        print('MESSAGE: ${e.message}');
      } else {
        print('EXCEPTION: $e');
      }
      print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      // No rethrow for tracking calls to avoid disrupting UX
    }
  }

  /// Fetch perspectives for a content via Google News search
  Future<PerspectivesResponse> getPerspectives(String contentId) async {
    try {
      final response = await _apiClient.dio.get<Map<String, dynamic>>(
        'contents/$contentId/perspectives',
      );

      if (response.statusCode == 200 && response.data != null) {
        return PerspectivesResponse.fromJson(response.data!);
      }
      throw Exception('Failed to load perspectives: ${response.statusCode}');
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] getPerspectives: $e');
      // Return empty response instead of throwing to not break UX
      return PerspectivesResponse(
          perspectives: [], keywords: [], biasDistribution: {});
    }
  }
}

/// Response from perspectives API
class PerspectivesResponse {
  final List<PerspectiveData> perspectives;
  final List<String> keywords;
  final Map<String, int> biasDistribution;

  PerspectivesResponse({
    required this.perspectives,
    required this.keywords,
    required this.biasDistribution,
  });

  factory PerspectivesResponse.fromJson(Map<String, dynamic> json) {
    final perspectivesList = (json['perspectives'] as List<dynamic>?)
            ?.map((e) => PerspectiveData.fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];

    final keywordsList = (json['keywords'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        [];

    final biasMap = <String, int>{};
    final rawBias = json['bias_distribution'] as Map<String, dynamic>?;
    if (rawBias != null) {
      rawBias.forEach((key, value) {
        biasMap[key] = (value as num?)?.toInt() ?? 0;
      });
    }

    return PerspectivesResponse(
      perspectives: perspectivesList,
      keywords: keywordsList,
      biasDistribution: biasMap,
    );
  }
}

/// Individual perspective data
class PerspectiveData {
  final String title;
  final String url;
  final String sourceName;
  final String sourceDomain;
  final String biasStance;
  final String? publishedAt;

  PerspectiveData({
    required this.title,
    required this.url,
    required this.sourceName,
    required this.sourceDomain,
    required this.biasStance,
    this.publishedAt,
  });

  factory PerspectiveData.fromJson(Map<String, dynamic> json) {
    return PerspectiveData(
      title: (json['title'] as String?) ?? '',
      url: (json['url'] as String?) ?? '',
      sourceName: (json['source_name'] as String?) ?? 'Unknown',
      sourceDomain: (json['source_domain'] as String?) ?? '',
      biasStance: (json['bias_stance'] as String?) ?? 'unknown',
      publishedAt: json['published_at'] as String?,
    );
  }
}
