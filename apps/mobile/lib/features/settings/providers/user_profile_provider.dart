import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modèle pour le profil utilisateur
class UserProfile {
  final String? displayName;

  const UserProfile({
    this.displayName,
  });

  UserProfile copyWith({
    String? displayName,
  }) {
    return UserProfile(
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'display_name': displayName,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      displayName: json['display_name'] as String?,
    );
  }
}

/// Notifier pour le profil utilisateur
class UserProfileNotifier extends StateNotifier<UserProfile> {
  UserProfileNotifier() : super(const UserProfile()) {
    _loadProfile();
  }

  final _supabase = Supabase.instance.client;
  static const String _boxName = 'user_profile';
  static const String _displayNameKey = 'display_name';

  Future<void> _loadProfile() async {
    // 1. Load from Hive cache first
    final box = await Hive.openBox<dynamic>(_boxName);
    final cachedDisplayName = box.get(_displayNameKey) as String?;

    if (cachedDisplayName != null) {
      state = UserProfile(
        displayName: cachedDisplayName,
      );
    }

    // 2. Fetch from Supabase
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await _supabase
          .from('user_profiles')
          .select('display_name')
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        state = UserProfile.fromJson(response);
        // Update cache
        await box.put(_displayNameKey, state.displayName);
      }
    } catch (e) {
      // Silently fail and use cached data
    }
  }

  Future<void> updateProfile({String? displayName}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Update state
    state = state.copyWith(
      displayName: displayName,
    );

    // Update Hive cache
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_displayNameKey, displayName);

    // Update Supabase
    try {
      await _supabase.from('user_profiles').update({
        'display_name': displayName,
      }).eq('user_id', userId);
    } catch (e) {
      // Silently fail - data is cached locally
    }
  }
}

/// Provider pour le profil utilisateur
final userProfileProvider =
    StateNotifierProvider<UserProfileNotifier, UserProfile>(
  (ref) => UserProfileNotifier(),
);
