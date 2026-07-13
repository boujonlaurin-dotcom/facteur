import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/gamification/models/streak_activity_model.dart';
import 'package:facteur/features/gamification/models/streak_model.dart';
import 'package:facteur/features/gamification/providers/gamification_preference_provider.dart';
import 'package:facteur/features/gamification/providers/streak_activity_provider.dart';
import 'package:facteur/features/gamification/providers/streak_animation_provider.dart';
import 'package:facteur/features/gamification/providers/streak_celebration_provider.dart';
import 'package:facteur/features/gamification/providers/streak_provider.dart';
import 'package:facteur/features/gamification/widgets/streak_indicator.dart';

class _FakeStreakNotifier extends StreakNotifier {
  _FakeStreakNotifier(this._model);

  final StreakModel _model;

  @override
  FutureOr<StreakModel> build() => _model;
}

Widget _wrap(List<Override> overrides, {bool reduceMotion = false}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      // MediaQuery placé **sous** le MaterialApp (qui recrée le sien via
      // `fromView`) pour que `disableAnimations` atteigne le widget testé, tout
      // en conservant la taille de la surface.
      home: Builder(
        builder: (context) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
          ),
          child: const Scaffold(body: Center(child: StreakIndicator())),
        ),
      ),
    ),
  );
}

void main() {
  const streak = StreakModel(
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
    expect(find.text('En ce moment'), findsOneWidget);
    expect(find.text('14 derniers jours'), findsOneWidget);
    expect(
      find.text('Une flamme marque les jours où Facteur a été ouvert.'),
      findsOneWidget,
    );
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

  group('célébration streak (N-1 → N)', () {
    const three = StreakModel(
      currentStreak: 3,
      longestStreak: 8,
      weeklyCount: 2,
      weeklyGoal: 5,
      weeklyProgress: 0.4,
    );

    setUp(() {
      SharedPreferences.setMockInitialValues(<String, Object>{});
    });

    List<Override> celebrationOverrides({
      required bool pending,
      required bool eligible,
    }) {
      return [
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        streakDailyAnimationProvider.overrideWith((ref) async => false),
        streakActivityProvider.overrideWith((ref) async => activity),
        streakProvider.overrideWith(() => _FakeStreakNotifier(three)),
        streakCelebrationEligibleProvider.overrideWith((ref) async => eligible),
        pendingStreakCelebrationProvider.overrideWith((ref) => pending),
        streakAnimationClockProvider.overrideWithValue(
          () => DateTime.utc(2026, 5, 26, 9), // 11h Paris → dayKey 2026-05-26
        ),
      ];
    }

    testWidgets('grows then ticks 2 → 3 and marks the gate', (tester) async {
      await tester.pumpWidget(
        _wrap(celebrationOverrides(pending: true, eligible: true)),
      );
      // Laisse les futures (gamification puis eligible/streak) se résoudre, puis
      // le post-frame (awaits prefs) poser l'override N-1.
      await tester.pump(); // gamification
      await tester.pump(); // eligible + streak → override = N-1 (build-time)
      await tester.pump(); // post-frame : lance le grow
      await tester.pump(const Duration(milliseconds: 32));

      // Avant le pic du grow : la flamme révèle N-1 (« 2 ») — l'incrément n'a
      // pas encore éclos (`findsWidgets` : le « 3 » réel peut encore finir son
      // fondu sortant dans l'AnimatedSwitcher).
      expect(find.text('2'), findsWidgets);

      // Passé le pic (~0.55 × 900ms) : bascule N-1 → N.
      await tester.pump(const Duration(milliseconds: 700));
      expect(find.text('3'), findsOneWidget);

      await tester.pumpAndSettle();
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing);

      // Gate 1×/jour-tournée consommé.
      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('streak_celebration_last_shown_date'),
        '2026-05-26',
      );
    });

    testWidgets('gate already posed (not eligible) → static 3, no N-1 flash', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(celebrationOverrides(pending: true, eligible: false)),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      // Aucune célébration : « 3 » d'emblée, jamais « 2 ».
      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing);
    });

    testWidgets('reduce-motion → shows 3 directly, gate marked', (
      tester,
    ) async {
      await tester.pumpWidget(
        _wrap(
          celebrationOverrides(pending: true, eligible: true),
          reduceMotion: true,
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 32));

      expect(find.text('3'), findsOneWidget);
      expect(find.text('2'), findsNothing);

      final prefs = await SharedPreferences.getInstance();
      expect(
        prefs.getString('streak_celebration_last_shown_date'),
        '2026-05-26',
      );
    });
  });
}
