import '../../../core/api/api_client.dart';
import '../models/source_model.dart';

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
}
