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

      final response = await _apiClient.dio.get<List<dynamic>>(
        '/feed',
        queryParameters: queryParams,
      );

      if (response.statusCode == 200) {
        final data = response.data;
        if (data == null) {
          return FeedResponse(
            items: [],
            pagination: Pagination(
                page: page, perPage: limit, total: 0, hasNext: false),
          );
        }

        final items = data
            .map((e) => Content.fromJson(e as Map<String, dynamic>))
            .toList();

        // On infère la pagination car le backend ne donne pas de métadonnées
        // Si on a reçu 'limit' items, on suppose qu'il y a une page suivante
        final hasNext = items.length >= limit;

        return FeedResponse(
          items: items,
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

  Future<void> toggleSave(String contentId, bool isSaved) async {
    try {
      if (isSaved) {
        await _apiClient.dio.post<void>('/contents/$contentId/save');
      } else {
        await _apiClient.dio.delete<void>('/contents/$contentId/save');
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
        '/contents/$contentId/hide',
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
        '/contents/$contentId/status',
        data: {'status': status.name.toUpperCase()},
      );
    } catch (e) {
      // ignore: avoid_print
      print('FeedRepository: [ERROR] updateContentStatus: $e');
      // No rethrow for tracking calls to avoid disrupting UX
    }
  }
}
