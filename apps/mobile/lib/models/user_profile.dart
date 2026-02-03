/// Modèle représentant le profil utilisateur
class UserProfile {
  final String id;
  final String userId;
  final String? displayName;
  final String ageRange;
  final String? gender;
  final bool onboardingCompleted;
  final bool gamificationEnabled;
  final int weeklyGoal;
  final DateTime createdAt;
  final DateTime updatedAt;

  const UserProfile({
    required this.id,
    required this.userId,
    this.displayName,
    required this.ageRange,
    this.gender,
    required this.onboardingCompleted,
    required this.gamificationEnabled,
    required this.weeklyGoal,
    required this.createdAt,
    required this.updatedAt,
  });

  /// Créer un UserProfile depuis JSON (API response)
  factory UserProfile.fromJson(Map<String, dynamic> json) {
    try {
      return UserProfile(
        id: (json['id'] as String?) ?? '',
        userId: (json['user_id'] as String?) ?? '',
        displayName: json['display_name'] as String?,
        ageRange: (json['age_range'] as String?) ?? 'unknown',
        gender: json['gender'] as String?,
        onboardingCompleted: (json['onboarding_completed'] as bool?) ?? false,
        gamificationEnabled: (json['gamification_enabled'] as bool?) ?? true,
        weeklyGoal: (json['weekly_goal'] as num?)?.toInt() ?? 10,
        createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
            DateTime.now(),
        updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? '') ??
            DateTime.now(),
      );
    } catch (e) {
      // ignore: avoid_print
      print('UserProfile.fromJson: Error parsing: $e');
      // On renvoie un objet minimal plutôt que de crash
      return UserProfile(
        id: (json['id'] as String?) ?? 'error',
        userId: (json['user_id'] as String?) ?? '',
        ageRange: 'unknown',
        onboardingCompleted: false,
        gamificationEnabled: true,
        weeklyGoal: 10,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
    }
  }

  /// Convertir en JSON
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'user_id': userId,
      'display_name': displayName,
      'age_range': ageRange,
      'gender': gender,
      'onboarding_completed': onboardingCompleted,
      'gamification_enabled': gamificationEnabled,
      'weekly_goal': weeklyGoal,
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
    };
  }

  /// Copier avec modifications
  UserProfile copyWith({
    String? id,
    String? userId,
    String? displayName,
    String? ageRange,
    String? gender,
    bool? onboardingCompleted,
    bool? gamificationEnabled,
    int? weeklyGoal,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      ageRange: ageRange ?? this.ageRange,
      gender: gender ?? this.gender,
      onboardingCompleted: onboardingCompleted ?? this.onboardingCompleted,
      gamificationEnabled: gamificationEnabled ?? this.gamificationEnabled,
      weeklyGoal: weeklyGoal ?? this.weeklyGoal,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  @override
  String toString() {
    return 'UserProfile(id: $id, userId: $userId, onboardingCompleted: $onboardingCompleted)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is UserProfile &&
        other.id == id &&
        other.userId == userId &&
        other.displayName == displayName &&
        other.ageRange == ageRange &&
        other.gender == gender &&
        other.onboardingCompleted == onboardingCompleted &&
        other.gamificationEnabled == gamificationEnabled &&
        other.weeklyGoal == weeklyGoal;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      userId,
      displayName,
      ageRange,
      gender,
      onboardingCompleted,
      gamificationEnabled,
      weeklyGoal,
    );
  }
}
