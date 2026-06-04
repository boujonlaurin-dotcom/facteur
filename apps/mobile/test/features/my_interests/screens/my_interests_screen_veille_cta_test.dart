import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/custom_topics/providers/personalization_provider.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/screens/my_interests_screen.dart';

/// Régression #639 : le call site de `_CreateVeilleCta` avait été supprimé par
/// mégarde dans `_buildBody()`, rendant la feature veille invisible pour tout
/// user sans veille préexistante. Ces tests verrouillent la visibilité
/// conditionnelle du CTA pour éviter une récidive.

/// Stub qui renvoie un état figé sans toucher au repository.
class _StubUserInterestsNotifier extends UserInterestsNotifier {
  _StubUserInterestsNotifier(this._state);

  final UserInterestsState _state;

  @override
  Future<UserInterestsState> build() async => _state;
}

/// Stub seedé sur l'état Serein voulu (sans appel réseau de persistance).
class _StubSereinToggleNotifier extends SereinToggleNotifier {
  _StubSereinToggleNotifier(super.ref, bool enabled) {
    state = SereinToggleState(enabled: enabled, isLoading: false);
  }
}

UserInterestsState _stateWithoutVeille() {
  return const UserInterestsState(
    themes: [],
    customTopics: [],
    favorites: [
      ThemeFavoriteRef(slug: 'environment'),
    ],
    favoriteCount: 1,
    favoriteCap: 5,
  );
}

UserInterestsState _stateWithVeille() {
  return const UserInterestsState(
    themes: [],
    customTopics: [],
    favorites: [
      ThemeFavoriteRef(slug: 'environment'),
      VeilleFavoriteRef(id: 'veille-uuid'),
    ],
    favoriteCount: 2,
    favoriteCap: 5,
  );
}

Widget _host({
  required UserInterestsState interests,
  required bool sereinMode,
}) {
  return ProviderScope(
    overrides: [
      userInterestsProvider.overrideWith(
        () => _StubUserInterestsNotifier(interests),
      ),
      sereinToggleProvider.overrideWith(
        (ref) => _StubSereinToggleNotifier(ref, sereinMode),
      ),
      // Évite tout appel réseau du bloc "Types de contenu" (mode normal).
      personalizationProvider.overrideWith(
        (ref) async => const UserPersonalization(),
      ),
    ],
    child: MaterialApp(
      theme: ThemeData(extensions: [FacteurPalettes.light]),
      home: const MyInterestsScreen(),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('MyInterestsScreen — CTA "Crée ta veille"', () {
    testWidgets('visible quand aucune veille en favori et mode normal',
        (tester) async {
      await tester.pumpWidget(
        _host(interests: _stateWithoutVeille(), sereinMode: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Crée ta veille'), findsOneWidget);
    });

    testWidgets('masqué quand une veille existe déjà en favori',
        (tester) async {
      await tester.pumpWidget(
        _host(interests: _stateWithVeille(), sereinMode: false),
      );
      await tester.pumpAndSettle();

      expect(find.text('Crée ta veille'), findsNothing);
    });

    testWidgets('masqué en mode sérène même sans veille', (tester) async {
      await tester.pumpWidget(
        _host(interests: _stateWithoutVeille(), sereinMode: true),
      );
      await tester.pumpAndSettle();

      expect(find.text('Crée ta veille'), findsNothing);
    });
  });
}
