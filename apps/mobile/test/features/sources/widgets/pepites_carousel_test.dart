import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/widgets/pepites_carousel.dart';

class _FakePepitesNotifier extends PepitesNotifier {
  _FakePepitesNotifier(this._initial);
  final List<Source> _initial;
  int dismissCalls = 0;

  @override
  Future<List<Source>> build() async => _initial;

  @override
  Future<void> dismiss() async {
    dismissCalls++;
    state = const AsyncValue.data([]);
  }
}

class _FakeUserSourcesStateNotifier extends UserSourcesStateNotifier {
  _FakeUserSourcesStateNotifier(this._initial);
  final UserSourcesState _initial;
  int setStateCalls = 0;
  String? lastSourceId;
  InterestState? lastState;

  @override
  Future<UserSourcesState> build() async => _initial;

  @override
  Future<void> setSourceState(String sourceId, InterestState newState) async {
    setStateCalls++;
    lastSourceId = sourceId;
    lastState = newState;
    final current = state.value ?? _initial;
    final sources = [...current.sources];
    final idx = sources.indexWhere((s) => s.sourceId == sourceId);
    if (idx >= 0) {
      sources[idx] = sources[idx].copyWith(state: newState);
    } else {
      sources.add(
        SourceInterest(
          sourceId: sourceId,
          state: newState,
          priorityMultiplier: 1,
        ),
      );
    }
    state = AsyncValue.data(current.copyWith(sources: sources));
  }
}

class _FakeUserSourcesNotifier extends UserSourcesNotifier {
  @override
  Future<List<Source>> build() async => const [];
}

void main() {
  group('PepitesCarousel', () {
    final mockSources = [
      Source(
        id: '1',
        name: 'Le Grand Continent',
        type: SourceType.article,
        theme: 'international',
        followerCount: 340,
      ),
      Source(
        id: '2',
        name: 'Next.ink',
        type: SourceType.article,
        theme: 'tech',
        followerCount: 128,
      ),
    ];

    Widget wrap({
      required List<Source> sources,
      _FakePepitesNotifier? notifier,
      _FakeUserSourcesStateNotifier? sourcesState,
    }) {
      final fake = notifier ?? _FakePepitesNotifier(sources);
      final fakeSourcesState =
          sourcesState ??
          _FakeUserSourcesStateNotifier(
            const UserSourcesState(
              sources: [],
              favorites: [],
              favoriteCount: 0,
              favoriteCap: 3,
            ),
          );
      return ProviderScope(
        overrides: [
          pepitesProvider.overrideWith(() => fake),
          userSourcesProvider.overrideWith(() => _FakeUserSourcesNotifier()),
          userSourcesStateProvider.overrideWith(() => fakeSourcesState),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const Scaffold(body: PepitesCarousel()),
        ),
      );
    }

    testWidgets('renders title and source cards when data loaded', (
      tester,
    ) async {
      await tester.pumpWidget(wrap(sources: mockSources));
      await tester.pumpAndSettle();

      expect(find.text("Recos. de l'équipe Facteur"), findsOneWidget);
      expect(find.text('Le Grand Continent'), findsOneWidget);
      expect(find.text('Next.ink'), findsOneWidget);
    });

    testWidgets('renders nothing when list is empty', (tester) async {
      await tester.pumpWidget(wrap(sources: const []));
      await tester.pumpAndSettle();

      expect(find.text("Recos. de l'équipe Facteur"), findsNothing);
    });

    testWidgets('dismiss button calls notifier.dismiss', (tester) async {
      final fake = _FakePepitesNotifier(mockSources);
      await tester.pumpWidget(wrap(sources: mockSources, notifier: fake));
      await tester.pumpAndSettle();

      final dismiss = find.bySemanticsLabel('Masquer les recommandations');
      expect(dismiss, findsOneWidget);

      await tester.tap(dismiss);
      await tester.pumpAndSettle();

      expect(fake.dismissCalls, 1);
      expect(find.text('Le Grand Continent'), findsNothing);
    });

    testWidgets('follow button uses canonical source state provider', (
      tester,
    ) async {
      final fakeSourcesState = _FakeUserSourcesStateNotifier(
        const UserSourcesState(
          sources: [],
          favorites: [],
          favoriteCount: 0,
          favoriteCap: 3,
        ),
      );
      await tester.pumpWidget(
        wrap(sources: mockSources, sourcesState: fakeSourcesState),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Suivre').first);
      await tester.pumpAndSettle();

      expect(fakeSourcesState.setStateCalls, 1);
      expect(fakeSourcesState.lastSourceId, '1');
      expect(fakeSourcesState.lastState, InterestState.followed);
      expect(find.text('Suivi'), findsOneWidget);
    });

    testWidgets('followed and favorite states render as Suivi', (tester) async {
      await tester.pumpWidget(
        wrap(
          sources: mockSources,
          sourcesState: _FakeUserSourcesStateNotifier(
            const UserSourcesState(
              sources: [
                SourceInterest(
                  sourceId: '1',
                  state: InterestState.favorite,
                  priorityMultiplier: 1,
                ),
                SourceInterest(
                  sourceId: '2',
                  state: InterestState.followed,
                  priorityMultiplier: 1,
                ),
              ],
              favorites: [],
              favoriteCount: 0,
              favoriteCap: 3,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Suivi'), findsNWidgets(2));
      expect(find.text('Suivre'), findsNothing);
    });
  });
}
