// Story Essentiel UX — carte de perso affichée sous le hero tant que la Tournée
// n'est pas personnalisée. Rendu (titre + illustration + CTA) et tap → la sheet
// unifiée « Mes favoris » s'ouvre.
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/digest/providers/serein_toggle_provider.dart';
import 'package:facteur/features/flux_continu/widgets/personalisation_cta_card.dart';
import 'package:facteur/features/grille/providers/grille_provider.dart';
import 'package:facteur/features/grille/repositories/grille_repository.dart';
import 'package:facteur/features/grille/models/grille_models.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/providers/veille_active_config_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _StubInterests extends UserInterestsNotifier {
  @override
  Future<UserInterestsState> build() async => const UserInterestsState(
        themes: [],
        customTopics: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 5,
      );
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

class _FakeGrilleRepository implements GrilleRepository {
  @override
  Future<GrilleTodayResponse> getToday() async =>
      throw Exception('mock: no grille');
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  Widget host() => ProviderScope(
        overrides: [
          userInterestsProvider.overrideWith(() => _StubInterests()),
          userSourcesStateProvider.overrideWith(() => _StubSources()),
          userSourcesProvider.overrideWith(() => _StubCatalog()),
          veilleActiveConfigProvider.overrideWith(() => _StubVeille()),
          grilleRepositoryProvider.overrideWithValue(_FakeGrilleRepository()),
          sereinToggleProvider.overrideWith((ref) => _StubSerein(ref)),
        ],
        child: MaterialApp(
          theme: ThemeData(
            extensions: [FacteurPalettes.light],
            splashFactory: NoSplash.splashFactory,
          ),
          home: const Scaffold(
            body: SingleChildScrollView(child: PersonalisationCtaCard()),
          ),
        ),
      );

  testWidgets('rend le titre, l\'illustration et le CTA', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    expect(find.text('Personnalise ton Essentiel'), findsOneWidget);
    expect(find.text('Composer ma Tournée'), findsOneWidget);
    expect(
      find.image(
        const AssetImage('assets/images/facteur_reparation_velo.png'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('tap sur le CTA ouvre la sheet « Mes favoris »', (tester) async {
    await tester.pumpWidget(host());
    await tester.pumpAndSettle();

    await tester.tap(find.text('Composer ma Tournée'));
    await tester.pumpAndSettle();

    expect(find.text('Mes favoris'), findsOneWidget);
  });
}
