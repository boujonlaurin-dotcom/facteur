import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/gamification/models/streak_model.dart';
import 'package:facteur/features/gamification/providers/gamification_preference_provider.dart';
import 'package:facteur/features/gamification/providers/streak_provider.dart';
import 'package:facteur/features/lettres/widgets/daily_goal_card.dart';

class _FakeStreakNotifier extends StreakNotifier {
  _FakeStreakNotifier(this._model);

  final StreakModel _model;

  @override
  FutureOr<StreakModel> build() => _model;
}

class _LoadingStreakNotifier extends StreakNotifier {
  @override
  FutureOr<StreakModel> build() => Completer<StreakModel>().future;
}

Widget _wrap(List<Override> overrides) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: const Scaffold(
        body: SingleChildScrollView(child: DailyGoalCard()),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  const streak = StreakModel(
    currentStreak: 3,
    longestStreak: 5,
    weeklyCount: 2,
    weeklyGoal: 10,
    weeklyProgress: 0.2,
    dailyGoal: 5,
  );

  testWidgets('affiche l\'objectif courant et le curseur quand la '
      'gamification est active', (tester) async {
    await tester.pumpWidget(
      _wrap([
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        streakProvider.overrideWith(() => _FakeStreakNotifier(streak)),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Objectif quotidien'), findsOneWidget);
    expect(find.text('5 articles'), findsOneWidget);
    expect(find.byType(Slider), findsOneWidget);

    final slider = tester.widget<Slider>(find.byType(Slider));
    expect(slider.value, 5.0);
    expect(slider.min, 1.0);
    expect(slider.max, 7.0);
    expect(slider.divisions, 6);
  });

  testWidgets('reste masquée quand la gamification est désactivée', (
    tester,
  ) async {
    await tester.pumpWidget(
      _wrap([
        gamificationPreferenceProvider.overrideWith((ref) async => false),
        streakProvider.overrideWith(() => _FakeStreakNotifier(streak)),
      ]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Objectif quotidien'), findsNothing);
    expect(find.byType(Slider), findsNothing);
  });

  testWidgets('retombe sur 2 articles sans valeur de streak', (tester) async {
    await tester.pumpWidget(
      _wrap([
        gamificationPreferenceProvider.overrideWith((ref) async => true),
        // Streak en cours de chargement → valeur indisponible → défaut 2.
        streakProvider.overrideWith(_LoadingStreakNotifier.new),
      ]),
    );
    await tester.pump();

    expect(find.text('2 articles'), findsOneWidget);
  });
}
