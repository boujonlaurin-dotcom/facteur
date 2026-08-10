import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/alerts/models/alert_item.dart';
import 'package:facteur/features/alerts/providers/alerts_provider.dart';
import 'package:facteur/features/alerts/screens/my_alerts_screen.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';

/// Inventaire figé : `build()` surchargé, donc ni repository ni auth.
class _FakeAlerts extends AlertsNotifier {
  _FakeAlerts(this._value);

  final AlertsState _value;

  @override
  Future<AlertsState> build() async => _value;
}

class _FakeSourcesState extends UserSourcesStateNotifier {
  _FakeSourcesState(this._value);

  final UserSourcesState _value;

  @override
  Future<UserSourcesState> build() async => _value;
}

class _FakeInterests extends UserInterestsNotifier {
  _FakeInterests(this._value);

  final UserInterestsState _value;

  @override
  Future<UserInterestsState> build() async => _value;
}

class _FakeCatalog extends UserSourcesNotifier {
  _FakeCatalog(this._value);

  final List<Source> _value;

  @override
  Future<List<Source>> build() async => _value;
}

const _sourceId = 'src-1';
const _topicId = 'topic-1';

Widget _wrap(AlertsState alerts) {
  return ProviderScope(
    overrides: [
      alertsProvider.overrideWith(() => _FakeAlerts(alerts)),
      userSourcesStateProvider.overrideWith(
        () => _FakeSourcesState(
          const UserSourcesState(
            sources: [
              SourceInterest(
                sourceId: _sourceId,
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
      userSourcesProvider.overrideWith(
        () => _FakeCatalog([
          Source(id: _sourceId, name: 'Le Canard', type: SourceType.article),
        ]),
      ),
      userInterestsProvider.overrideWith(
        () => _FakeInterests(
          const UserInterestsState(
            themes: [],
            customTopics: [
              CustomTopicInterest(
                id: _topicId,
                topicName: 'Ligue 1',
                slugParent: 'sport',
                state: InterestState.favorite,
                priorityMultiplier: 1,
              ),
            ],
            favorites: [],
            favoriteCount: 0,
            favoriteCap: 5,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const MyAlertsScreen(),
    ),
  );
}

void main() {
  testWidgets(
    "l'en-tête porte le plafond, la vérité sur le push et le geste d'ajout",
    (tester) async {
      await tester.pumpWidget(_wrap(const AlertsState()));
      await tester.pumpAndSettle();

      expect(find.text('0 alerte sur 5'), findsOneWidget);
      expect(
        find.textContaining('dès la parution, avec son'),
        findsOneWidget,
      );
      expect(find.text('Ajouter une alerte'), findsOneWidget);
    },
  );

  testWidgets('plus aucun réglage qui ne change rien', (tester) async {
    await tester.pumpWidget(
      _wrap(
        AlertsState(
          items: [
            AlertItem(sourceId: _sourceId, sourceName: 'Le Canard'),
          ],
          activeCount: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Quand me prévenir'), findsNothing);
    expect(find.text('Récap hebdo'), findsNothing);
    expect(find.text('Dans ma tournée'), findsNothing);
  });

  testWidgets('plafond atteint : le geste est fermé et expliqué',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        AlertsState(
          items: [
            for (var i = 0; i < 5; i++)
              AlertItem(sourceId: 'src-$i', sourceName: 'Source $i'),
          ],
          activeCount: 5,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('5 alertes sur 5'), findsOneWidget);
    expect(
      find.textContaining('Plafond atteint'),
      findsOneWidget,
    );
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Ajouter une alerte'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets("l'état vide ne renvoie plus hors de l'écran", (tester) async {
    await tester.pumpWidget(_wrap(const AlertsState()));
    await tester.pumpAndSettle();

    expect(find.text('Aucune alerte pour l\'instant'), findsOneWidget);
    // La v1 envoyait chercher une fiche ailleurs ; le geste est ici.
    expect(find.text('Voir mes sources'), findsNothing);
    expect(find.text('Ajouter une alerte'), findsOneWidget);
  });

  testWidgets(
    'le sélecteur propose les sources ET les sujets suivis, sans quitter '
    "l'écran",
    (tester) async {
      await tester.pumpWidget(_wrap(const AlertsState()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Ajouter une alerte'));
      await tester.pumpAndSettle();

      expect(find.text('Poser une alerte'), findsOneWidget);
      expect(find.text('Le Canard'), findsOneWidget);
      expect(find.text('Ligue 1'), findsOneWidget);
      // On est toujours sur « Mes alertes » : la feuille est modale.
      expect(find.byType(MyAlertsScreen), findsOneWidget);
    },
  );

  testWidgets('une cible déjà sous cloche est signalée, pas reproposée',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        AlertsState(
          items: [
            AlertItem(sourceId: _sourceId, sourceName: 'Le Canard'),
          ],
          activeCount: 1,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajouter une alerte'));
    await tester.pumpAndSettle();

    expect(find.text('Déjà alerté'), findsOneWidget);
  });

  testWidgets('la recherche filtre les cibles', (tester) async {
    await tester.pumpWidget(_wrap(const AlertsState()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Ajouter une alerte'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), 'ligue');
    await tester.pumpAndSettle();

    expect(find.text('Ligue 1'), findsOneWidget);
    expect(find.text('Le Canard'), findsNothing);
  });
}
