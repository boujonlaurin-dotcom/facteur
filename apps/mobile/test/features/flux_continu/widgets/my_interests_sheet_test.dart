import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/my_interests_sheet.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';

/// Stub UserInterestsNotifier that returns a fixed state. The sheet reads
/// directly from userInterestsProvider so this is enough to drive the test
/// without hitting the (absent) repository.
class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._state);

  final UserInterestsState _state;

  @override
  Future<UserInterestsState> build() async => _state;
}

UserInterestsState _stateWithFavorites() {
  return const UserInterestsState(
    themes: [],
    customTopics: [
      CustomTopicInterest(
        id: 'topic-uuid',
        topicName: 'IA & éducation',
        slugParent: 'tech',
        state: InterestState.favorite,
        priorityMultiplier: 2.0,
      ),
    ],
    favorites: [
      CustomTopicFavoriteRef(id: 'topic-uuid'),
      ThemeFavoriteRef(slug: 'environment'),
    ],
    favoriteCount: 2,
    favoriteCap: 3,
  );
}

Widget _openerHost(UserInterestsState interests) {
  return ProviderScope(
    overrides: [
      userInterestsProvider.overrideWith(
        () => _StubUserInterestsNotifier(interests),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showMyInterestsBottomSheet(ctx),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('showMyInterestsBottomSheet', () {
    testWidgets(
        'lists only theme/veille favorites (custom topics excluded) + CTA',
        (tester) async {
      await tester.pumpWidget(_openerHost(_stateWithFavorites()));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Mes intérêts'), findsOneWidget);
      // Le sujet précis (custom topic) est exclu : seul le thème compte.
      expect(find.text('1 FAVORIS'), findsOneWidget);
      expect(find.text('IA & éducation'), findsNothing);
      // Theme slug → canonical visual label
      expect(find.text('Environnement'), findsOneWidget);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('02'), findsNothing);
      // Copie clarifiant la séparation thèmes ↔ sujets.
      expect(find.text('Tes sujets précis se gèrent dans Flâner.'),
          findsOneWidget);
      expect(find.text('Gérer mes intérêts'), findsOneWidget);
      expect(find.text('Fermer'), findsOneWidget);
    });

    testWidgets('shows the empty hint when there are no favorites',
        (tester) async {
      await tester.pumpWidget(_openerHost(const UserInterestsState(
        themes: [],
        customTopics: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 3,
      )));

      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Aucun favori pour le moment.'), findsOneWidget);
      expect(find.text('0 FAVORIS'), findsOneWidget);
    });

    testWidgets('Fermer dismisses the sheet', (tester) async {
      await tester.pumpWidget(_openerHost(_stateWithFavorites()));
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();

      expect(find.text('Mes intérêts'), findsOneWidget);
      await tester.tap(find.text('Fermer'));
      await tester.pumpAndSettle();
      expect(find.text('Mes intérêts'), findsNothing);
    });
  });
}
