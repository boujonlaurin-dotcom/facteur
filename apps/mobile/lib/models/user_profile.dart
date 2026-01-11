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
    return UserProfile(
      id: json['id'] as String,
      userId: json['user_id'] as String,
      displayName: json['display_name'] as String?,
      ageRange: json['age_range'] as String,
      gender: json['gender'] as String?,
      onboardingCompleted: json['onboarding_completed'] as bool,
      gamificationEnabled: json['gamification_enabled'] as bool,
      weeklyGoal: json['weekly_goal'] as int,
      createdAt: DateTime.parse(json['created_at'] as String),
      updatedAt: DateTime.parse(json['updated_at'] as String),
    );
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

