import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/providers/selected_edition_date_provider.dart';
import 'package:facteur/features/flux_continu/utils/morning_ritual_format.dart';
import 'package:facteur/features/flux_continu/widgets/edition_timeline_sheet.dart';
import 'package:facteur/features/gamification/models/streak_activity_model.dart';
import 'package:facteur/features/gamification/providers/streak_activity_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Court-circuite le vrai `FluxContinuNotifier` (build réseau lourd) : fournit
/// un Essentiel déterministe (ou rien).
class _StubFlux extends FluxContinuNotifier {
  _StubFlux(this.articles);
  final List<EssentielArticle> articles;

  @override
  Future<FluxContinuState> build() async => FluxContinuState(
        sections: articles.isEmpty
            ? const []
            : [EssentielSection(articles: articles)],
        isLoading: false,
      );
}

EssentielArticle _article(int rank) => EssentielArticle(
      contentId: 'c-$rank',
      title: 'Titre $rank',
      url: 'https://example.com/$rank',
      publishedAt: DateTime(2026, 6, 23),
      sourceName: 'Le Monde',
      sourceLetter: 'L',
      sectionLabel: 'Tech',
      rank: rank,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  /// Ouvre la feuille via l'API publique `EditionTimelineSheet.show`. Par défaut
  /// streaks indisponible (set vide) → aucune pastille (rendu déterministe).
  Future<ProviderContainer> openSheet(
    WidgetTester tester, {
    StreakActivityModel activity = const StreakActivityModel.empty(),
    List<EssentielArticle> todayArticles = const [],
  }) async {
    final container = ProviderContainer(overrides: [
      fluxContinuProvider.overrideWith(() => _StubFlux(todayArticles)),
      streakActivityProvider.overrideWith((ref) async => activity),
    ]);
    addTearDown(container.dispose);
    // Surface haute : la feuille (maxHeight 85%) doit pouvoir poser ses 3 lignes
    // (today, hier, cette semaine) sans en clipper (sinon le ListView.builder ne
    // construit pas les lignes hors écran et `find.text` ne les trouve pas).
    tester.view.physicalSize = const Size(440, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: ThemeData(extensions: [FacteurPalettes.light]),
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => EditionTimelineSheet.show(context),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    return container;
  }

  /// Décoration du conteneur de ligne (ancêtre Container le plus proche du label).
  BoxDecoration rowDeco(WidgetTester tester, String label) {
    final container = tester.widget<Container>(
      find.ancestor(of: find.text(label), matching: find.byType(Container)).first,
    );
    return container.decoration as BoxDecoration;
  }

  Finder rowOf(String label) =>
      find.ancestor(of: find.text(label), matching: find.byType(Container)).first;

  testWidgets('rend les 3 lignes (today, Hier, Cette semaine)',
      (tester) async {
    await openSheet(tester);
    expect(find.text('Remonter le temps'), findsOneWidget);
    final model = editionPillModel();
    final ordered = <EditionSelection>[
      const EditionToday(),
      ...model.whereType<EditionPastDay>(),
      const EditionWeek(),
    ];
    // Rewind à 3 options : aujourd'hui + 1 jour passé (hier) + cette semaine.
    expect(ordered.length, 3);
    for (final sel in ordered) {
      expect(find.text(editionPillLabel(sel)), findsOneWidget,
          reason: 'ligne manquante : ${editionPillLabel(sel)}');
    }
  });

  testWidgets('today affiche le compte d\'articles quand connu', (tester) async {
    await openSheet(tester, todayArticles: [_article(1), _article(2), _article(3)]);
    expect(find.textContaining('3 articles'), findsOneWidget);
  });

  testWidgets('tap d\'une ligne → sélection mise à jour + feuille fermée',
      (tester) async {
    final container = await openSheet(tester);
    await tester.tap(find.text('Hier'));
    await tester.pumpAndSettle();

    final sel = container.read(selectedEditionDateProvider);
    expect(sel, isA<EditionPastDay>());
    final j1 = editionPastDays(1).first;
    expect(editionDayKey((sel as EditionPastDay).date), editionDayKey(j1));
    // Feuille refermée.
    expect(find.text('Remonter le temps'), findsNothing);
  });

  testWidgets('la ligne active (sélection courante) est cerclée', (tester) async {
    await openSheet(tester); // défaut = Aujourd'hui
    expect(rowDeco(tester, 'Aujourd’hui').border, isNotNull);
    expect(rowDeco(tester, 'Hier').border, isNull);
  });

  testWidgets(
      'statut : streaks dispo → pastilles correctes ; today = À jour',
      (tester) async {
    final today = editionTodayDate();
    final past = editionPastDays(kEditionMaxPastDays);
    final activity = StreakActivityModel(
      currentStreak: 1,
      longestStreak: 1,
      days: [
        StreakActivityDay(date: today, opened: true),
        StreakActivityDay(date: past[0], opened: true), // J-1 (Hier) lu
        for (var i = 1; i < past.length; i++)
          StreakActivityDay(date: past[i], opened: false),
      ],
    );
    await openSheet(tester, activity: activity);

    expect(
      find.descendant(of: rowOf('Aujourd’hui'), matching: find.text('À jour')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: rowOf('Hier'), matching: find.text('À jour')),
      findsOneWidget,
    );
    // « Cette semaine » agrège J-0…J-6 ; J-2…J-6 jamais ouverts → « Non lu ».
    expect(find.text('Non lu'), findsWidgets);
  });

  testWidgets('statut : streaks indisponible → aucune pastille', (tester) async {
    await openSheet(tester); // activity vide par défaut → unavailable
    expect(find.text('À jour'), findsNothing);
    expect(find.text('Non lu'), findsNothing);
  });

  testWidgets('EditionRewindTrigger : tap déclenche le callback', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: EditionRewindTrigger(label: 'Hier', onTap: () => taps++),
        ),
      ),
    );
    expect(find.text('Hier'), findsOneWidget);
    await tester.tap(find.byType(EditionRewindTrigger));
    await tester.pump();
    expect(taps, 1);
  });
}
