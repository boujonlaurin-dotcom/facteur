/// Story 22.1 — repository des endpoints `/api/user/interests` et `/api/user/sources`.
library;

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../config/constants.dart';
import '../../../core/api/api_client.dart';
import '../../../core/api/providers.dart';
import '../models/user_interests_state.dart';
import '../models/user_sources_state.dart';

/// Erreur typée pour le 422 `favorite_cap_reached` (intérêts ou sources).
class FavoriteCapReachedException implements Exception {
  final int cap;
  const FavoriteCapReachedException(this.cap);

  @override
  String toString() => 'FavoriteCapReachedException(cap=$cap)';
}

class UserInterestsRepository {
  final ApiClient _client;

  UserInterestsRepository(this._client);

  Future<UserInterestsState> fetchInterests() async {
    final data = await _client.get('user/interests');
    return UserInterestsState.fromJson(data as Map<String, dynamic>);
  }

  /// `PATCH /api/user/interests` — mute l'état d'un Thème ou Sujet.
  /// Lève [FavoriteCapReachedException] si le backend renvoie 422 favorite_cap_reached.
  Future<UserInterestsState> setInterestState({
    required FavoriteRef ref,
    required InterestState state,
    int? position,
  }) async {
    try {
      final data = await _client.dio.patch<dynamic>(
        'user/interests',
        data: {
          'kind': ref.kind,
          'target_id': ref.targetId,
          'state': state.toJson(),
          if (position != null) 'position': position,
        },
      );
      return UserInterestsState.fromJson(data.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _maybeThrowCap(e);
      rethrow;
    }
  }

  Future<UserInterestsState> reorderFavorites(List<FavoriteRef> ordered) async {
    final payload = {
      'favorites': [
        for (var i = 0; i < ordered.length; i++)
          {
            ...ordered[i].toJson(),
            'position': i,
          }
      ],
    };
    final data = await _client.post('user/interests/reorder', body: payload);
    return UserInterestsState.fromJson(data as Map<String, dynamic>);
  }

  Future<UserSourcesState> fetchSourcesState() async {
    final data = await _client.get('user/sources');
    return UserSourcesState.fromJson(data as Map<String, dynamic>);
  }

  Future<UserSourcesState> setSourceState({
    required String sourceId,
    required InterestState state,
    int? position,
  }) async {
    try {
      final data = await _client.dio.patch<dynamic>(
        'user/sources',
        data: {
          'source_id': sourceId,
          'state': state.toJson(),
          if (position != null) 'position': position,
        },
      );
      return UserSourcesState.fromJson(data.data as Map<String, dynamic>);
    } on DioException catch (e) {
      _maybeThrowCap(e);
      rethrow;
    }
  }

  Future<UserSourcesState> reorderSourceFavorites(
      List<SourceFavoriteRef> ordered) async {
    final payload = {
      'favorites': [
        for (var i = 0; i < ordered.length; i++)
          {
            'source_id': ordered[i].sourceId,
            'position': i,
          }
      ],
    };
    final data = await _client.post('user/sources/reorder', body: payload);
    return UserSourcesState.fromJson(data as Map<String, dynamic>);
  }

  /// Traduit 422 `favorite_cap_reached` en [FavoriteCapReachedException].
  /// Format backend : `{ "detail": { "error": "favorite_cap_reached", "cap": 5 } }`.
  void _maybeThrowCap(DioException e) {
    if (e.response?.statusCode != 422) return;
    final raw = e.response?.data;
    if (raw is Map && raw['detail'] is Map) {
      final detail = raw['detail'] as Map;
      if (detail['error'] == 'favorite_cap_reached') {
        final cap = (detail['cap'] as num?)?.toInt() ?? kFavoriteCap;
        throw FavoriteCapReachedException(cap);
      }
    }
  }
}

final userInterestsRepositoryProvider =
    Provider<UserInterestsRepository>((ref) {
  final client = ref.watch(apiClientProvider);
  return UserInterestsRepository(client);
});
