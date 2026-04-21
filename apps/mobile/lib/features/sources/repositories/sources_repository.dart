import '../../../core/api/api_client.dart';
import '../models/smart_search_result.dart';
import '../models/source_model.dart';
import '../models/theme_source_model.dart';

class SourcesRepository {
  final ApiClient _apiClient;

  SourcesRepository(this._apiClient);

  Future<List<Source>> getAllSources() async {
    try {
      final response = await _apiClient.dio.get<dynamic>('sources');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data == null) return [];

        if (data is List) {
          return data
              .map((json) => Source.fromJson(json as Map<String, dynamic>))
              .toList();
        } else if (data is Map<String, dynamic>) {
          // Possible object wrapper or error
          if (data.containsKey('curated')) {
            final result = <Source>[];
            if (data['curated'] != null) {
              result.addAll((data['curated'] as List).map(
                  (json) => Source.fromJson(json as Map<String, dynamic>)));
            }
            if (data['custom'] != null) {
              result.addAll((data['custom'] as List).map(
                  (json) => Source.fromJson(json as Map<String, dynamic>)));
            }
            return result;
          }
          // Log unexpected map
          print(
              'SourcesRepository: [WARNING] Received Map but expected List or Catalog: $data');
        }
        return [];
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getAllSources: $e');
      rethrow;
    }
  }

  Future<List<Source>> getTrendingSources({int limit = 10}) async {
    try {
      final response = await _apiClient.dio
          .get<dynamic>('sources/trending', queryParameters: {'limit': limit});
      if (response.statusCode == 200) {
        final data = response.data;
        if (data is List) {
          return data
              .map((json) => Source.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getTrendingSources: $e');
      return [];
    }
  }

  Future<void> trustSource(String sourceId) async {
    try {
      await _apiClient.dio.post<dynamic>('sources/$sourceId/trust');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] trustSource: $e');
      rethrow;
    }
  }

  Future<void> untrustSource(String sourceId) async {
    try {
      await _apiClient.dio.delete<dynamic>('sources/$sourceId/trust');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] untrustSource: $e');
      rethrow;
    }
  }

  Future<Map<String, dynamic>> detectSource(String url) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'sources/detect',
        data: {'url': url},
      );
      if (response.statusCode == 200 && response.data != null) {
        return response.data!;
      }
      throw Exception('Failed to detect source');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] detectSource: $e');
      rethrow;
    }
  }

  Future<void> updateSourceWeight(
      String sourceId, double priorityMultiplier) async {
    try {
      await _apiClient.dio.put<dynamic>(
        'sources/$sourceId/weight',
        data: {'priority_multiplier': priorityMultiplier},
      );
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] updateSourceWeight: $e');
      rethrow;
    }
  }

  Future<void> updateSourceSubscription(
      String sourceId, bool hasSubscription) async {
    try {
      await _apiClient.dio.put<dynamic>(
        'sources/$sourceId/subscription',
        data: {'has_subscription': hasSubscription},
      );
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] updateSourceSubscription: $e');
      rethrow;
    }
  }

  Future<void> addCustomSource(String url, {String? name}) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'sources/custom',
        data: {'url': url, if (name != null) 'name': name},
      );
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] addCustomSource: $e');
      rethrow;
    }
  }

  Future<SmartSearchResponse> smartSearch(
    String query, {
    String? contentType,
    bool expand = false,
  }) async {
    try {
      final response = await _apiClient.dio.post<Map<String, dynamic>>(
        'sources/smart-search',
        data: {
          'query': query,
          if (contentType != null) 'content_type': contentType,
          if (expand) 'expand': true,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        return SmartSearchResponse.fromJson(response.data!);
      }
      throw Exception('Smart search failed');
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] smartSearch: $e');
      rethrow;
    }
  }

  Future<List<FollowedTheme>> getThemesFollowed() async {
    try {
      final response =
          await _apiClient.dio.get<dynamic>('sources/themes-followed');
      if (response.statusCode == 200 && response.data is Map) {
        final themes = (response.data as Map<String, dynamic>)['themes'];
        if (themes is List) {
          return themes
              .map((json) =>
                  FollowedTheme.fromJson(json as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getThemesFollowed: $e');
      return [];
    }
  }

  Future<void> logSearchAbandoned(String query) async {
    try {
      await _apiClient.dio.post<dynamic>(
        'sources/search-abandoned',
        data: {'query': query},
      );
    } catch (_) {
      // fire-and-forget
    }
  }

  Future<ThemeSourcesResponse> getSourcesByTheme(String slug) async {
    try {
      final response =
          await _apiClient.dio.get<dynamic>('sources/by-theme/$slug');
      if (response.statusCode == 200 && response.data is Map) {
        return ThemeSourcesResponse.fromJson(
            response.data as Map<String, dynamic>);
      }
      return const ThemeSourcesResponse(
          curated: [], candidates: [], community: []);
    } catch (e) {
      // ignore: avoid_print
      print('SourcesRepository: [ERROR] getSourcesByTheme: $e');
      rethrow;
    }
  }
}
