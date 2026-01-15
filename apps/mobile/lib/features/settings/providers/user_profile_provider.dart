import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Modèle pour le profil utilisateur
class UserProfile {
  final String? firstName;
  final String? lastName;

  const UserProfile({
    this.firstName,
    this.lastName,
  });

  UserProfile copyWith({
    String? firstName,
    String? lastName,
  }) {
    return UserProfile(
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'first_name': firstName,
      'last_name': lastName,
    };
  }

  factory UserProfile.fromJson(Map<String, dynamic> json) {
    return UserProfile(
      firstName: json['first_name'] as String?,
      lastName: json['last_name'] as String?,
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
  static const String _firstNameKey = 'first_name';
  static const String _lastNameKey = 'last_name';

  Future<void> _loadProfile() async {
    // 1. Load from Hive cache first
    final box = await Hive.openBox<dynamic>(_boxName);
    final cachedFirstName = box.get(_firstNameKey) as String?;
    final cachedLastName = box.get(_lastNameKey) as String?;

    if (cachedFirstName != null || cachedLastName != null) {
      state = UserProfile(
        firstName: cachedFirstName,
        lastName: cachedLastName,
      );
    }

    // 2. Fetch from Supabase
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    try {
      final response = await _supabase
          .from('user_profiles')
          .select('first_name, last_name')
          .eq('user_id', userId)
          .maybeSingle();

      if (response != null) {
        state = UserProfile.fromJson(response);
        // Update cache
        await box.put(_firstNameKey, state.firstName);
        await box.put(_lastNameKey, state.lastName);
      }
    } catch (e) {
      // Silently fail and use cached data
    }
  }

  Future<void> updateProfile({String? firstName, String? lastName}) async {
    final userId = _supabase.auth.currentUser?.id;
    if (userId == null) return;

    // Update state
    state = state.copyWith(
      firstName: firstName,
      lastName: lastName,
    );

    // Update Hive cache
    final box = await Hive.openBox<dynamic>(_boxName);
    await box.put(_firstNameKey, firstName);
    await box.put(_lastNameKey, lastName);

    // Update Supabase
    try {
      await _supabase.from('user_profiles').update({
        'first_name': firstName,
        'last_name': lastName,
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
