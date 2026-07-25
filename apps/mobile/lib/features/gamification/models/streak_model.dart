class StreakModel {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityDate;
  final int weeklyCount;
  final int weeklyGoal;
  final double weeklyProgress;

  /// Lectures abouties de la journée éditoriale (frontière 07h30 Paris).
  /// Dérivé côté serveur de `completed_at`, jamais stocké.
  final int dailyCompleted;

  /// Objectif du jour. Constante serveur : recalibrable sans release client.
  final int dailyGoal;

  const StreakModel({
    required this.currentStreak,
    required this.longestStreak,
    this.lastActivityDate,
    required this.weeklyCount,
    required this.weeklyGoal,
    required this.weeklyProgress,
    this.dailyCompleted = 0,
    this.dailyGoal = 2,
  });

  /// L'objectif du jour est atteint. Volontairement pas exposé comme cible
  /// avant l'effort : il ne sert qu'à un constat rétrospectif.
  bool get dailyGoalReached => dailyCompleted >= dailyGoal;

  factory StreakModel.fromJson(Map<String, dynamic> json) {
    return StreakModel(
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      lastActivityDate: json['last_activity_date'] != null
          ? DateTime.tryParse(json['last_activity_date'] as String)
          : null,
      weeklyCount: json['weekly_count'] as int? ?? 0,
      weeklyGoal: json['weekly_goal'] as int? ?? 10,
      weeklyProgress: (json['weekly_progress'] as num?)?.toDouble() ?? 0.0,
      dailyCompleted: json['daily_completed'] as int? ?? 0,
      dailyGoal: json['daily_goal'] as int? ?? 2,
    );
  }

  StreakModel copyWith({
    int? currentStreak,
    int? longestStreak,
    DateTime? lastActivityDate,
    int? weeklyCount,
    int? weeklyGoal,
    double? weeklyProgress,
    int? dailyCompleted,
    int? dailyGoal,
  }) {
    return StreakModel(
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastActivityDate: lastActivityDate ?? this.lastActivityDate,
      weeklyCount: weeklyCount ?? this.weeklyCount,
      weeklyGoal: weeklyGoal ?? this.weeklyGoal,
      weeklyProgress: weeklyProgress ?? this.weeklyProgress,
      dailyCompleted: dailyCompleted ?? this.dailyCompleted,
      dailyGoal: dailyGoal ?? this.dailyGoal,
    );
  }
}
