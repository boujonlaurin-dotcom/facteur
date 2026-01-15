import '../../../core/api/api_client.dart';
import '../models/source_model.dart';

class SourcesRepository {
  final ApiClient _apiClient;

  SourcesRepository(this._apiClient);

  Future<List<Source>> getAllSources() async {
    try {
      final response =
          await _apiClient.dio.get<List<dynamic>>('sources/catalog');

      if (response.statusCode == 200) {
        final data = response.data;
        if (data == null) return [];
        return data
            .map((json) => Source.fromJson(json as Map<String, dynamic>))
            .toList();
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
}
