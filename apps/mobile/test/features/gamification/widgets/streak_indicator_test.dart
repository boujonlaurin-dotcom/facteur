import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/gamification/models/streak_activity_model.dart';
import 'package:facteur/features/gamification/models/streak_model.dart';
import 'package:facteur/features/gamification/providers/gamification_preference_provider.dart';
import 'package:facteur/features/gamification/providers/streak_activity_provider.dart';
import 'package:facteur/features/gamification/providers/streak_animation_provider.dart';
import 'package:facteur/features/gamification/providers/streak_provider.dart';
import 'package:facteur/features/gamification/widgets/streak_indicator.dart';

class _FakeStreakNotifier extends StreakNotifier {
  _FakeStreakNotifier(this._model);

  final StreakModel _model;

  @override
  FutureOr<StreakModel> build() => _model;
}

Widget _wrap(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const Scaffold(body: Center(child: StreakIndicator())),
    ),
  );
}

void main() {
  final streak = StreakModel(
    currentStreak: 5,
    longestStreak: 8,
    weeklyCount: 2,
    weeklyGoal: 5,
    weeklyProgress: 0.4,
  );
  final activity = StreakActivityModel.fromJson({
    'current_streak': 5,
    'longest_streak': 8,
    'last_activity_date': '2026-05-26',
    'days': List.generate(
      14,
      (index) => {
        'date': DateTime(
          2026,
          5,
          13 + index,
        ).toIso8601String().split('T').first,
        'opened': index.isEven,
      },
    ),
  });

  testWidgets('streak indicator is tappable and opens the explainer modal', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        streakDailyAnimationProvider.overrideWith((ref) async => false),
        streakActivityProvider.overrideWith((ref) async => activity),
        streakProvider.overrideWith(() => _FakeStreakNotifier(streak)),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('5'), findsOneWidget);

    await tester.tap(find.text('5'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Ta série d\'ouverture'), findsOneWidget);
    expect(find.text('14 derniers jours'), findsOneWidget);
  });

  testWidgets('streak indicator is hidden when gamification is disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        gamificationPreferenceProvider.overrideWith((ref) async => false),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('5'), findsNothing);
    expect(find.byType(InkWell), findsNothing);
  });
}
