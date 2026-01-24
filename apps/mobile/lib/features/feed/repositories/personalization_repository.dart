import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/api/providers.dart';
import '../../../core/api/api_client.dart';

final personalizationRepositoryProvider =
    Provider((ref) => PersonalizationRepository(ref.read(apiClientProvider)));

class PersonalizationRepository {
  final ApiClient _apiClient;

  PersonalizationRepository(this._apiClient);

  Future<void> muteSource(String sourceId) async {
    await _apiClient.post(
      'users/personalization/mute-source',
      body: {'source_id': sourceId},
    );
  }

  Future<void> muteTheme(String theme) async {
    await _apiClient.post(
      'users/personalization/mute-theme',
      body: {'theme': theme},
    );
  }

  Future<void> muteTopic(String topic) async {
    await _apiClient.post(
      'users/personalization/mute-topic',
      body: {'topic': topic},
    );
  }

  Future<void> unmuteSource(String sourceId) async {
    await _apiClient.delete('users/personalization/unmute-source/$sourceId');
  }
}
