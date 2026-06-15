class StreakActivityDay {
  final DateTime date;
  final bool opened;
  final int? articlesRead;

  const StreakActivityDay({
    required this.date,
    required this.opened,
    this.articlesRead,
  });

  factory StreakActivityDay.fromJson(Map<String, dynamic> json) {
    return StreakActivityDay(
      date: DateTime.parse(json['date'] as String),
      opened: json['opened'] as bool? ?? false,
      articlesRead: (json['articles_read'] as num?)?.toInt(),
    );
  }
}

class StreakActivityModel {
  final int currentStreak;
  final int longestStreak;
  final DateTime? lastActivityDate;
  final List<StreakActivityDay> days;

  const StreakActivityModel({
    required this.currentStreak,
    required this.longestStreak,
    this.lastActivityDate,
    required this.days,
  });

  factory StreakActivityModel.fromJson(Map<String, dynamic> json) {
    return StreakActivityModel(
      currentStreak: json['current_streak'] as int? ?? 0,
      longestStreak: json['longest_streak'] as int? ?? 0,
      lastActivityDate: json['last_activity_date'] != null
          ? DateTime.tryParse(json['last_activity_date'] as String)
          : null,
      days: (json['days'] as List<dynamic>? ?? const <dynamic>[])
          .whereType<Map<String, dynamic>>()
          .map(StreakActivityDay.fromJson)
          .toList(),
    );
  }

  const StreakActivityModel.empty()
    : currentStreak = 0,
      longestStreak = 0,
      lastActivityDate = null,
      days = const <StreakActivityDay>[];
}
