import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/api/providers.dart';
import '../../../core/api/user_api_service.dart';
import '../../../models/user_profile.dart' as app_model;

class GamificationPreferenceRepository {
  GamificationPreferenceRepository(this._userApiService);

  final UserApiService _userApiService;
  static const _boxName = 'user_profile';
  static const _profileKey = 'profile';
  static const _gamificationKey = 'gamification_enabled';

  Future<bool> load() async {
    final cached = await _readCachedValue();

    try {
      final profile = await _userApiService.getProfile();
      if (profile != null) {
        await _writeCache(profile);
        return profile.gamificationEnabled;
      }
    } catch (_) {
      // Best-effort: keep using the cached value when the profile call fails.
    }

    return cached ?? true;
  }

  Future<bool?> _readCachedValue() async {
    final box = await Hive.openBox<dynamic>(_boxName);
    final cachedFlag = box.get(_gamificationKey);
    if (cachedFlag is bool) return cachedFlag;

    final cachedProfile = box.get(_profileKey);
    if (cachedProfile is Map) {
      final profile = app_model.UserProfile.fromJson(
        Map<String, dynamic>.from(cachedProfile),
      );
      return profile.gamificationEnabled;
    }

    return null;
  }

  Future<void> _writeCache(app_model.UserProfile profile) async {
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_profileKey, profile.toJson());
    await box.put(_gamificationKey, profile.gamificationEnabled);
  }
}

final gamificationPreferenceRepositoryProvider =
    Provider<GamificationPreferenceRepository>((ref) {
  return GamificationPreferenceRepository(
    ref.watch(userApiServiceProvider),
  );
});

final gamificationPreferenceProvider = FutureProvider<bool>((ref) async {
  final repository = ref.watch(gamificationPreferenceRepositoryProvider);
  return repository.load();
});
