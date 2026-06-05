// Story 10.2 — `PinSubjectsBanner` est inchangé (CTA d'épinglage). Son onTap
// (et `showPinSubjectsSheet`) ouvre désormais la sheet unifiée
// [showManageFavoritesSheet] côté Flâner. La couverture détaillée du contenu
// vit dans `manage_favorites_sheet_test.dart`.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/feed/widgets/pin_subjects_sheet.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_active_config_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeUserInterestsNotifier extends UserInterestsNotifier {
  _FakeUserInterestsNotifier(this._initial);
  final UserInterestsState _initial;

  @override
  Future<UserInterestsState> build() async => _initial;

  @override
  Future<void> setInterestState(FavoriteRef ref, InterestState s) async {}
}

class _StubSources extends UserSourcesStateNotifier {
  @override
  Future<UserSourcesState> build() async => const UserSourcesState(
        sources: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 5,
      );
}

class _StubCatalog extends UserSourcesNotifier {
  @override
  Future<List<Source>> build() async => const [];
}

class _StubVeille extends VeilleActiveConfigNotifier {
  @override
  Future<VeilleConfigDto?> build() async => null;
}

class _NoGrille implements GrilleRepository {
  @override
  Future<GrilleTodayResponse> getToday() => throw Exception('no grille');
  @override
  Future<GrilleLeaderboardResponse> getLeaderboard() =>
      throw UnimplementedError();
  @override
  Future<GrilleRevealResponse> revealWord() => throw UnimplementedError();
  @override
  Future<GrilleGuessResponse> submitGuess(String mot) =>
      throw UnimplementedError();
}

class _StubSerein extends SereinToggleNotifier {
  _StubSerein(super.ref) {
    state = const SereinToggleState(enabled: false, isLoading: false);
  }
}

CustomTopicInterest _topic(String id, String name, InterestState state) =>
    CustomTopicInterest(
      id: id,
      topicName: name,
      slugParent: 'tech',
      state: state,
      priorityMultiplier: state == InterestState.favorite ? 2.0 : 1.0,
    );

UserInterestsState _state(List<CustomTopicInterest> topics) {
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

Widget _bannerHost(UserInterestsState interests, Widget child) => ProviderScope(
      overrides: [
        userInterestsProvider.overrideWith(
          () => _FakeUserInterestsNotifier(interests),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData(
          extensions: [FacteurPalettes.light],
          splashFactory: NoSplash.splashFactory,
        ),
        home: Scaffold(body: child),
      ),
    );

Widget _sheetHost(UserInterestsState interests, Widget child) => ProviderScope(
      overrides: [
        userInterestsProvider.overrideWith(
          () => _FakeUserInterestsNotifier(interests),
        ),
        userSourcesStateProvider.overrideWith(() => _StubSources()),
        userSourcesProvider.overrideWith(() => _StubCatalog()),
        veilleActiveConfigProvider.overrideWith(() => _StubVeille()),
        grilleRepositoryProvider.overrideWithValue(_NoGrille()),
        sereinToggleProvider.overrideWith((ref) => _StubSerein(ref)),
      ],
      child: MaterialApp(
        theme: ThemeData(
          extensions: [FacteurPalettes.light],
          splashFactory: NoSplash.splashFactory,
        ),
        home: Scaffold(body: child),
      ),
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  group('PinSubjectsBanner', () {
    testWidgets('visible when fewer than 3 subjects are pinned',
        (tester) async {
      final st = _state([_topic('t1', 'Sujet A', InterestState.favorite)]);
      await tester.pumpWidget(_bannerHost(st, const PinSubjectsBanner()));
      await tester.pumpAndSettle();

      expect(
        find.text('Épinglez des sources ou sujets précis'),
        findsOneWidget,
      );
    });

    testWidgets('hidden when 3 or more subjects are pinned', (tester) async {
      final st = _state([
        _topic('t1', 'Sujet A', InterestState.favorite),
        _topic('t2', 'Sujet B', InterestState.favorite),
        _topic('t3', 'Sujet C', InterestState.favorite),
      ]);
      await tester.pumpWidget(_bannerHost(st, const PinSubjectsBanner()));
      await tester.pumpAndSettle();

      expect(
        find.text('Épinglez des sources ou sujets précis'),
        findsNothing,
      );
    });
  });

  group('showPinSubjectsSheet', () {
    testWidgets('ouvre la sheet unifiée « Mes favoris » côté Flâner',
        (tester) async {
      final st = _state([_topic('t1', 'Climat', InterestState.followed)]);

      await tester.pumpWidget(_sheetHost(
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

      expect(find.text('Mes favoris'), findsOneWidget);
      expect(find.text('TES ONGLETS POUR EXPLORER'), findsOneWidget);
      // Porte Flâner ⇒ segment « Sujets » présélectionné : le sujet suivi est
      // proposé à l'épinglage.
      expect(find.text('Climat'), findsOneWidget);
    });
  });
}
