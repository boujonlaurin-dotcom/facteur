import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/pin_subjects_sheet.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';

/// Fake notifier: serves a fixed state and applies setInterestState locally
/// (no repository), recording each call so tests can assert on pin/unpin.
class _FakeUserInterestsNotifier extends UserInterestsNotifier {
  _FakeUserInterestsNotifier(this._initial);

  final UserInterestsState _initial;
  final List<(FavoriteRef, InterestState)> calls = [];

  @override
  Future<UserInterestsState> build() async => _initial;

  @override
  Future<void> setInterestState(
    FavoriteRef refTarget,
    InterestState newState,
  ) async {
    calls.add((refTarget, newState));
    final current = state.value;
    if (current == null) return;
    final topics = [
      for (final t in current.customTopics)
        if (t.id == refTarget.targetId)
          t.copyWith(state: newState)
        else
          t,
    ];
    final favorites = [
      for (final f in current.favorites)
        if (f != refTarget) f,
      if (newState == InterestState.favorite) refTarget,
    ];
    state = AsyncData(current.copyWith(
      customTopics: topics,
      favorites: favorites,
      favoriteCount: favorites.length,
    ));
  }
}

CustomTopicInterest _topic(String id, String name, InterestState state) {
  return CustomTopicInterest(
    id: id,
    topicName: name,
    slugParent: 'tech',
    state: state,
    priorityMultiplier: state == InterestState.favorite ? 2.0 : 1.0,
  );
}

UserInterestsState _state({
  required List<CustomTopicInterest> topics,
}) {
  final favorites = <FavoriteRef>[
    for (final t in topics)
      if (t.state == InterestState.favorite) CustomTopicFavoriteRef(id: t.id),
  ];
  return UserInterestsState(
    themes: const [],
    customTopics: topics,
    favorites: favorites,
    favoriteCount: favorites.length,
    favoriteCap: 3,
  );
}

Widget _host(
  UserInterestsState interests,
  Widget child, {
  _FakeUserInterestsNotifier? notifier,
}) {
  return ProviderScope(
    overrides: [
      userInterestsProvider.overrideWith(
        () => notifier ?? _FakeUserInterestsNotifier(interests),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  group('PinSubjectsBanner', () {
    testWidgets('visible when fewer than 3 subjects are pinned',
        (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Sujet A', InterestState.favorite),
      ]);
      await tester.pumpWidget(_host(st, const PinSubjectsBanner()));
      await tester.pumpAndSettle();

      expect(find.text('Épingle tes sujets de veille'), findsOneWidget);
    });

    testWidgets('hidden when 3 or more subjects are pinned', (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Sujet A', InterestState.favorite),
        _topic('t2', 'Sujet B', InterestState.favorite),
        _topic('t3', 'Sujet C', InterestState.favorite),
      ]);
      await tester.pumpWidget(_host(st, const PinSubjectsBanner()));
      await tester.pumpAndSettle();

      expect(find.text('Épingle tes sujets de veille'), findsNothing);
    });
  });

  group('showPinSubjectsSheet', () {
    testWidgets('pins a followed subject in one tap', (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Climat', InterestState.followed),
      ]);
      final notifier = _FakeUserInterestsNotifier(st);

      await tester.pumpWidget(_host(
        st,
        Builder(
          builder: (ctx) => Center(
            child: ElevatedButton(
              onPressed: () => showPinSubjectsSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
        notifier: notifier,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Le sujet suivi est proposé à l'épinglage.
      expect(find.text('ÉPINGLER UN SUJET SUIVI'), findsOneWidget);
      expect(find.text('Climat'), findsOneWidget);

      await tester.tap(find.text('Climat'));
      await tester.pumpAndSettle();

      expect(notifier.calls, hasLength(1));
      expect(notifier.calls.first.$1, const CustomTopicFavoriteRef(id: 't1'));
      expect(notifier.calls.first.$2, InterestState.favorite);
      // Après épinglage il bascule dans la section « SUJETS ÉPINGLÉS ».
      expect(find.text('SUJETS ÉPINGLÉS'), findsOneWidget);
    });
  });
}
