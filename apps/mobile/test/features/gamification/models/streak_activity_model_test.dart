import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/gamification/models/streak_activity_model.dart';

void main() {
  test('parses streak activity payload', () {
    final model = StreakActivityModel.fromJson({
      'current_streak': 4,
      'longest_streak': 9,
      'last_activity_date': '2026-05-26',
      'days': [
        {'date': '2026-05-25', 'opened': true, 'articles_read': 2},
        {'date': '2026-05-26', 'opened': false},
      ],
    });

    expect(model.currentStreak, 4);
    expect(model.longestStreak, 9);
    expect(model.lastActivityDate, DateTime(2026, 5, 26));
    expect(model.days, hasLength(2));
    expect(model.days.first.opened, isTrue);
    expect(model.days.first.articlesRead, 2);
    expect(model.days.last.articlesRead, isNull);
  });
}
