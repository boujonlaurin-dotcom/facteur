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
        if (t.id == refTarget.targetId) t.copyWith(state: newState) else t,
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

CustomTopicInterest _topic(
  String id,
  String name,
  InterestState state, {
  String slugParent = 'tech',
}) {
  return CustomTopicInterest(
    id: id,
    topicName: name,
    slugParent: slugParent,
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
    favoriteCap: 5,
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
      // splashFactory NoSplash : évite le shader Material 3 `ink_sparkle.frag`,
      // absent du bundle `flutter test` (le tap d'une ligne sujet déclenche
      // sinon « Asset 'shaders/ink_sparkle.frag' not found »). Test-only.
      theme: ThemeData(
        extensions: [FacteurPalettes.light],
        splashFactory: NoSplash.splashFactory,
      ),
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

      expect(
        find.text('Épinglez des sources ou sujets précis'),
        findsOneWidget,
      );
    });

    testWidgets('hidden when 3 or more subjects are pinned', (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Sujet A', InterestState.favorite),
        _topic('t2', 'Sujet B', InterestState.favorite),
        _topic('t3', 'Sujet C', InterestState.favorite),
      ]);
      await tester.pumpWidget(_host(st, const PinSubjectsBanner()));
      await tester.pumpAndSettle();

      expect(find.text('Épingle tes sujets'), findsNothing);
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

      // La zone « SUIVIS » expose 2 onglets. Le sujet suivi est sous « Sujets ».
      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('Sujets'), findsOneWidget);
      await tester.tap(find.text('Sujets'));
      await tester.pumpAndSettle();
      expect(find.text('Climat'), findsOneWidget);

      await tester.tap(find.text('Climat'));
      await tester.pumpAndSettle();

      expect(notifier.calls, hasLength(1));
      expect(notifier.calls.first.$1, const CustomTopicFavoriteRef(id: 't1'));
      expect(notifier.calls.first.$2, InterestState.favorite);
      // Après épinglage il bascule dans la section « ÉPINGLÉS ».
      expect(find.text('ÉPINGLÉS'), findsOneWidget);
    });

    testWidgets('search filters the followed subjects', (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Climat', InterestState.followed),
        _topic('t2', 'Intelligence artificielle', InterestState.followed),
      ]);

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
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Les sujets suivis sont sous l'onglet « Sujets ».
      await tester.tap(find.text('Sujets'));
      await tester.pumpAndSettle();

      // Recherche insensible aux accents/casse.
      await tester.enterText(find.byType(TextField), 'clim');
      await tester.pumpAndSettle();

      expect(find.text('Climat'), findsOneWidget);
      expect(find.text('Intelligence artificielle'), findsNothing);
    });

    testWidgets('offers to create a subject when no match', (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Climat', InterestState.followed),
      ]);

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
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Zélande');
      await tester.pumpAndSettle();

      expect(find.text('Climat'), findsNothing);
      // La tuile « Créer le sujet » reprend la requête entre guillemets.
      expect(find.textContaining('Créer le sujet « Zélande »'), findsOneWidget);
    });

    testWidgets('lists followed subjects flat (no theme group headers)',
        (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Climat', InterestState.followed,
            slugParent: 'environment'),
        _topic('t2', 'IA', InterestState.followed, slugParent: 'tech'),
      ]);

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
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Sujets'));
      await tester.pumpAndSettle();

      // Liste à plat : les sujets sont là, mais plus d'en-têtes de thème.
      expect(find.text('Climat'), findsOneWidget);
      expect(find.text('IA'), findsOneWidget);
      expect(find.text('Technologie'), findsNothing);
      expect(find.text('Environnement'), findsNothing);
    });

    testWidgets('followed lists are split into 2 segments (Sources / Sujets)',
        (tester) async {
      final st = _state(topics: [
        _topic('t1', 'Climat', InterestState.followed),
      ]);

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
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      // Les 2 segments sont présents ; par défaut l'onglet Sources (vide ici).
      expect(find.byType(SegmentedButton<int>), findsOneWidget);
      expect(find.text('Sources'), findsOneWidget);
      expect(find.text('Sujets'), findsOneWidget);
      expect(find.text('Aucune source suivie'), findsOneWidget);
      // Le sujet suivi n'est visible qu'après bascule sur « Sujets ».
      expect(find.text('Climat'), findsNothing);
      await tester.tap(find.text('Sujets'));
      await tester.pumpAndSettle();
      expect(find.text('Climat'), findsOneWidget);
    });
  });
}
