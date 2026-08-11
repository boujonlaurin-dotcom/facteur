import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/alerts/models/alert_item.dart';
import 'package:facteur/features/alerts/models/alert_suggestion.dart';
import 'package:facteur/features/alerts/providers/alerts_provider.dart';
import 'package:facteur/features/alerts/screens/my_alerts_screen.dart';
import 'package:facteur/features/alerts/widgets/alert_suggestions_list.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/my_interests/providers/user_sources_state_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/settings/providers/notifications_settings_provider.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';

/// Inventaire pilotable : `setAlert` / `setTopicAlert` sont interceptés pour
/// que le test observe le vrai geste (le mode filtré transmis, la cloche qui
/// apparaît) sans réseau ni repository.
class _FakeAlerts extends AlertsNotifier {
  _FakeAlerts(this._value);

  AlertsState _value;

  final List<({String id, bool filtered, bool topic})> calls = [];

  @override
  Future<AlertsState> build() async => _value;

  @override
  Future<void> setAlert(String id, bool enabled, {bool filtered = false}) async {
    calls.add((id: id, filtered: filtered, topic: false));
    _value = AlertsState(
      items: [
        ..._value.items,
        AlertItem(sourceId: id, sourceName: 'Le Lu', filtered: filtered),
      ],
      activeCount: _value.activeCount + 1,
      cap: _value.cap,
    );
    state = AsyncData(_value);
  }

  @override
  Future<void> setTopicAlert(
    String id,
    bool enabled, {
    bool filtered = false,
  }) async {
    calls.add((id: id, filtered: filtered, topic: true));
    _value = AlertsState(
      items: [
        ..._value.items,
        AlertItem(
          kind: AlertKind.topic,
          sourceId: id,
          sourceName: 'Ligue 1',
          filtered: filtered,
        ),
      ],
      activeCount: _value.activeCount + 1,
      cap: _value.cap,
    );
    state = AsyncData(_value);
  }
}

/// Suggestions figées : `build()` surchargé, donc pas de repository. `dismiss`
/// garde le retrait local du vrai notifier mais coupe l'appel réseau.
class _FakeSuggestions extends AlertSuggestionsNotifier {
  _FakeSuggestions(this._value);

  final AlertSuggestionsState _value;

  final List<String> dismissed = [];

  @override
  Future<AlertSuggestionsState> build() async => _value;

  @override
  Future<void> dismiss(AlertSuggestion suggestion) async {
    dismissed.add(suggestion.targetId);
    final current = state.valueOrNull;
    if (current != null) {
      state = AsyncData(current.without(suggestion.targetId));
    }
  }
}

class _FakeSourcesState extends UserSourcesStateNotifier {
  @override
  Future<UserSourcesState> build() async => const UserSourcesState(
        sources: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 3,
      );
}

class _FakeInterests extends UserInterestsNotifier {
  @override
  Future<UserInterestsState> build() async => const UserInterestsState(
        themes: [],
        customTopics: [],
        favorites: [],
        favoriteCount: 0,
        favoriteCap: 5,
      );
}

class _FakeCatalog extends UserSourcesNotifier {
  @override
  Future<List<Source>> build() async => const [];
}

const _sourceSuggestion = AlertSuggestion(
  kind: AlertKind.source,
  targetId: 'src-1',
  targetName: 'Le Lu',
  reason: 'Tu as ouvert 8 articles sur 10 de cette source ce mois-ci.',
  signal: 'source_read',
  cadencePhrase: 'Publie environ 2 fois par semaine',
);

const _noisySuggestion = AlertSuggestion(
  kind: AlertKind.source,
  targetId: 'src-2',
  targetName: 'Le Robinet',
  reason: 'Tu as ouvert 5 articles de cette source ce mois-ci.',
  signal: 'source_read',
  cadencePhrase: 'Publie environ 3 fois par jour',
  noisy: true,
  prefillFiltered: true,
);

const _topicSuggestion = AlertSuggestion(
  kind: AlertKind.topic,
  targetId: 'topic-1',
  targetName: 'Ligue 1',
  reason: 'Tu ouvres régulièrement les articles sur ce sujet.',
  signal: 'topic_affinity',
  cadencePhrase: 'Publie environ une fois par semaine',
);

Widget _wrap({
  required AlertsState alerts,
  required AlertSuggestionsState suggestions,
  _FakeAlerts? alertsNotifier,
  _FakeSuggestions? suggestionsNotifier,
}) {
  return ProviderScope(
    overrides: [
      alertsProvider.overrideWith(() => alertsNotifier ?? _FakeAlerts(alerts)),
      alertSuggestionsProvider.overrideWith(
        () => suggestionsNotifier ?? _FakeSuggestions(suggestions),
      ),
      userSourcesStateProvider.overrideWith(_FakeSourcesState.new),
      userSourcesProvider.overrideWith(_FakeCatalog.new),
      userInterestsProvider.overrideWith(_FakeInterests.new),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const MyAlertsScreen(),
    ),
  );
}

/// Réveille le garde-fou de permission push **réel** (`ensureAlertPushPermission`,
/// extrait par le lot C) avant le tap : son état vient de Hive de façon
/// asynchrone, et il n'est instancié qu'à la première lecture. Sans ce
/// pré-chargement, la première lecture verrait `pushEnabled: false` et
/// ouvrirait la modale d'activation.
Future<void> _warmPushPermission(WidgetTester tester) async {
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MyAlertsScreen)),
  );
  container.read(notificationsSettingsProvider);
  await tester.pumpAndSettle();
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp();
    Hive.init(tempDir.path);
    final box = await Hive.openBox<dynamic>('settings');
    await box.put('push_notifications_enabled', true);
  });

  tearDown(() async {
    await Hive.deleteFromDisk();
  });

  testWidgets(
    'chaque suggestion porte son nom, sa raison et sa cadence',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          alerts: const AlertsState(),
          suggestions: const AlertSuggestionsState(
            suggestions: [_sourceSuggestion, _topicSuggestion],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Peut-être aussi'), findsOneWidget);
      expect(find.text('Le Lu'), findsOneWidget);
      expect(
        find.text('Tu as ouvert 8 articles sur 10 de cette source ce mois-ci.'),
        findsOneWidget,
      );
      expect(find.text('Publie environ 2 fois par semaine'), findsOneWidget);
      expect(find.text('Ligue 1'), findsOneWidget);
      expect(
        find.text('Tu ouvres régulièrement les articles sur ce sujet.'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    "une suggestion s'accepte en un tap et apparaît dans l'inventaire",
    (tester) async {
      final notifier = _FakeAlerts(const AlertsState());
      await tester.pumpWidget(
        _wrap(
          alerts: const AlertsState(),
          alertsNotifier: notifier,
          suggestions: const AlertSuggestionsState(
            suggestions: [_sourceSuggestion],
          ),
        ),
      );
      await tester.pumpAndSettle();

      // L'inventaire est vide avant le geste.
      expect(find.text('Aucune alerte pour l\'instant'), findsOneWidget);

      await _warmPushPermission(tester);
    await tester.tap(find.byTooltip('Poser l\'alerte'));
      await tester.pumpAndSettle();

      expect(notifier.calls.single.id, 'src-1');
      expect(notifier.calls.single.topic, isFalse);
      expect(find.text('1 alerte sur 5'), findsOneWidget);
      expect(find.text('Aucune alerte pour l\'instant'), findsNothing);
      expect(find.textContaining('Alerte posée sur Le Lu'), findsOneWidget);
    },
  );

  testWidgets(
    'une cible bruyante est posée avec le mode filtré déjà coché',
    (tester) async {
      final notifier = _FakeAlerts(const AlertsState());
      await tester.pumpWidget(
        _wrap(
          alerts: const AlertsState(),
          alertsNotifier: notifier,
          suggestions: const AlertSuggestionsState(
            suggestions: [_noisySuggestion],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Le mode filtré sera activé'),
        findsOneWidget,
      );

      await _warmPushPermission(tester);
    await tester.tap(find.byTooltip('Poser l\'alerte'));
      await tester.pumpAndSettle();

      expect(notifier.calls.single.filtered, isTrue);
      expect(
        find.textContaining('Seulement les plus marquantes'),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'le bloc reste actif après une première acceptation',
    (tester) async {
      // Régression : le verrou `_busyId` n'était relâché que dans les branches
      // d'erreur. Après une pose réussie il restait posé, et comme il gouverne
      // les gestes de *toutes* les lignes, le bloc entier devenait inerte
      // jusqu'à ce qu'on quitte l'écran.
      final notifier = _FakeAlerts(const AlertsState());
      final suggestions = _FakeSuggestions(
        const AlertSuggestionsState(
          suggestions: [_sourceSuggestion, _topicSuggestion],
        ),
      );
      await tester.pumpWidget(
        _wrap(
          alerts: const AlertsState(),
          alertsNotifier: notifier,
          suggestions: const AlertSuggestionsState(),
          suggestionsNotifier: suggestions,
        ),
      );
      await tester.pumpAndSettle();
      await _warmPushPermission(tester);

      await tester.tap(find.byTooltip('Poser l\'alerte').first);
      await tester.pumpAndSettle();
      expect(notifier.calls, hasLength(1));

      // La seconde ligne doit toujours répondre.
      await tester.tap(find.byTooltip('Poser l\'alerte').first);
      await tester.pumpAndSettle();

      expect(notifier.calls, hasLength(2));
      expect(notifier.calls.map((c) => c.id), ['src-1', 'topic-1']);
    },
  );

  testWidgets('un sujet passe bien par setTopicAlert', (tester) async {
    final notifier = _FakeAlerts(const AlertsState());
    await tester.pumpWidget(
      _wrap(
        alerts: const AlertsState(),
        alertsNotifier: notifier,
        suggestions: const AlertSuggestionsState(
          suggestions: [_topicSuggestion],
        ),
      ),
    );
    await tester.pumpAndSettle();

    await _warmPushPermission(tester);
    await tester.tap(find.byTooltip('Poser l\'alerte'));
    await tester.pumpAndSettle();

    expect(notifier.calls.single.topic, isTrue);
    expect(notifier.calls.single.id, 'topic-1');
  });

  testWidgets('une suggestion refusée disparaît et est mémorisée',
      (tester) async {
    final suggestions = _FakeSuggestions(
      const AlertSuggestionsState(
        suggestions: [_sourceSuggestion, _topicSuggestion],
      ),
    );
    await tester.pumpWidget(
      _wrap(
        alerts: const AlertsState(),
        suggestions: const AlertSuggestionsState(),
        suggestionsNotifier: suggestions,
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Ne plus proposer').first);
    await tester.pumpAndSettle();

    expect(suggestions.dismissed, ['src-1']);
    expect(find.text('Le Lu'), findsNothing);
    expect(find.text('Ligue 1'), findsOneWidget);
  });

  testWidgets(
    'au plafond, le bloc s\'efface et l\'écran explique au lieu de proposer',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          alerts: AlertsState(
            items: [
              for (var i = 0; i < 5; i++)
                AlertItem(sourceId: 'src-$i', sourceName: 'Source $i'),
            ],
            activeCount: 5,
          ),
          // Ce que rend le serveur au plafond : rien, et il le dit.
          suggestions: const AlertSuggestionsState(
            activeCount: 5,
            atCap: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AlertSuggestionsList), findsOneWidget);
      expect(find.text('Peut-être aussi'), findsNothing);
      expect(find.textContaining('Plafond atteint'), findsOneWidget);
    },
  );

  testWidgets('sans suggestion, le bloc n\'occupe aucune place',
      (tester) async {
    await tester.pumpWidget(
      _wrap(
        alerts: const AlertsState(),
        suggestions: const AlertSuggestionsState(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Peut-être aussi'), findsNothing);
    // `SizedBox.shrink` dans une `ListView` est étiré en largeur : c'est la
    // hauteur qui prouve que le bloc ne mange aucun pixel.
    expect(tester.getSize(find.byType(AlertSuggestionsList)).height, 0);
  });

  test('le retrait local ne touche que la cible visée', () {
    const state = AlertSuggestionsState(
      suggestions: [_sourceSuggestion, _topicSuggestion],
      activeCount: 2,
      cap: 5,
    );

    final next = state.without('src-1');

    expect(next.suggestions.map((s) => s.targetId), ['topic-1']);
    expect(next.cap, 5);
    expect(next.activeCount, 2);
  });

  test('le parseur tolère un backend qui ne renvoie rien d\'exploitable', () {
    final state = AlertSuggestionsState.fromJson({
      'cap': 5,
      'active_count': 1,
      'suggestions': [
        {'target_id': '', 'target_name': 'Sans identité'},
        {
          'kind': 'topic',
          'target_id': 'topic-9',
          'target_name': 'Ligue 1',
          'reason': 'Tu ouvres régulièrement les articles sur ce sujet.',
          'signal': 'topic_affinity',
          'prefill_filtered': true,
        },
      ],
    });

    expect(state.atCap, isFalse);
    expect(state.suggestions.length, 1);
    expect(state.suggestions.single.isTopic, isTrue);
    expect(state.suggestions.single.prefillFiltered, isTrue);
  });
}
