class StreakModel {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityDate;
  final int weeklyCount;
  final int weeklyGoal;
  final double weeklyProgress;

  StreakModel({
    required this.currentStreak,
    required this.longestStreak,
    this.lastActivityDate,
    required this.weeklyCount,
    required this.weeklyGoal,
    required this.weeklyProgress,
  });

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
    );
  }

  StreakModel copyWith({
    int? currentStreak,
    int? longestStreak,
    DateTime? lastActivityDate,
    int? weeklyCount,
    int? weeklyGoal,
    double? weeklyProgress,
  }) {
    return StreakModel(
      currentStreak: currentStreak ?? this.currentStreak,
      longestStreak: longestStreak ?? this.longestStreak,
      lastActivityDate: lastActivityDate ?? this.lastActivityDate,
      weeklyCount: weeklyCount ?? this.weeklyCount,
      weeklyGoal: weeklyGoal ?? this.weeklyGoal,
      weeklyProgress: weeklyProgress ?? this.weeklyProgress,
    );
  }
}
