// Story 30.4 — « la carte alerte *est* l'article ».
//
// Trois reproches PO verrouillés ici :
//   1. la carte cachait l'article derrière « N nouveaux » → elle montre le titre ;
//   2. le tap rebondissait sur `SourceSectionScreen` qui rechargeait tout
//      (3-4 s d'écran blanc) → il ouvre le lecteur avec le contenu en `extra` ;
//   3. une alerte sujet construisait `source:<user_topic_profiles.id>` et
//      tombait sur une liste vide → elle ne construit plus jamais cette route.
import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/alerts/models/alert_item.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/widgets/alerts_section_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

AlertContent _content({
  String id = 'c-1',
  String title = 'Le titre qui vient de sortir',
  String sourceName = 'Le Mensuel',
  DateTime? publishedAt,
}) {
  return AlertContent(
    contentId: id,
    title: title,
    url: 'https://example.com/$id',
    sourceId: 'src-$id',
    sourceName: sourceName,
    publishedAt: publishedAt ?? DateTime.now().subtract(const Duration(hours: 2)),
  );
}

AlertItem _alert({
  AlertKind kind = AlertKind.source,
  String id = 'a-1',
  String name = 'Le Mensuel',
  int newContent = 1,
  List<AlertContent> contents = const [],
}) {
  return AlertItem(
    kind: kind,
    sourceId: id,
    sourceName: name,
    newContent: newContent,
    contents: contents,
  );
}

/// Router minimal : on n'observe que la destination et l'`extra` du push.
class _Nav {
  String? location;
  Object? extra;
}

Future<_Nav> _pumpCard(WidgetTester tester, List<AlertItem> items) async {
  final nav = _Nav();
  final router = GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(
        path: '/',
        builder: (_, __) => Scaffold(
          body: SingleChildScrollView(
            child: AlertsSectionCard(section: AlertsSection(items: items)),
          ),
        ),
      ),
      GoRoute(
        path: '${RoutePaths.fluxContinu}/content/:id',
        builder: (_, state) {
          nav.location = state.uri.toString();
          nav.extra = state.extra;
          // Miroir de `ContentDetailScreen` : le header se peint depuis
          // l'`extra`, sans attendre `getContent()`.
          final preview = state.extra as Content?;
          return Scaffold(body: Text(preview?.title ?? 'CHARGEMENT'));
        },
      ),
      GoRoute(
        path: '${RoutePaths.fluxContinu}/source/:id',
        builder: (_, state) {
          nav.location = state.uri.toString();
          return const Scaffold(body: Text('SOURCE PAGE'));
        },
      ),
      GoRoute(
        path: RoutePaths.alerts,
        name: RouteNames.alerts,
        builder: (_, state) {
          nav.location = state.uri.toString();
          return const Scaffold(body: Text('MES ALERTES'));
        },
      ),
    ],
  );

  await tester.pumpWidget(
    MaterialApp.router(
      routerConfig: router,
      theme: ThemeData(
        extensions: [FacteurPalettes.light],
        splashFactory: NoSplash.splashFactory,
      ),
    ),
  );
  await tester.pumpAndSettle();
  return nav;
}

void main() {
  testWidgets('la carte affiche le titre de ce qui vient de sortir',
      (tester) async {
    await _pumpCard(tester, [
      _alert(contents: [_content(title: 'Grève des trains ce week-end')]),
    ]);

    expect(find.text('Grève des trains ce week-end'), findsOneWidget);
    // Le compteur nu ne remplace plus l'information.
    expect(find.text('1 nouveau'), findsNothing);
  });

  testWidgets('un tap ouvre le lecteur avec le contenu déjà en mémoire',
      (tester) async {
    final nav = await _pumpCard(tester, [
      _alert(contents: [_content(id: 'c-42', title: 'Un titre')]),
    ]);

    await tester.tap(find.text('Un titre'));
    await tester.pumpAndSettle();

    expect(nav.location, '/flux-continu/content/c-42');
    // L'`extra` est ce qui supprime l'écran blanc : le header est peint au
    // 1ᵉʳ frame sans attendre `getContent()`.
    final extra = nav.extra;
    expect(extra, isA<Content>());
    expect((extra! as Content).title, 'Un titre');
    expect((extra as Content).source.name, 'Le Mensuel');
  });

  testWidgets('le contenu est peint dès le 1ᵉʳ frame après le tap',
      (tester) async {
    // Le cœur du reproche PO : avant, le tap ouvrait `SourceSectionScreen` avec
    // `items: const []` et attendait `getFeed()` (3-4 s d'écran blanc). Ici, un
    // seul `pump` — donc zéro round-trip réseau — suffit à afficher le titre.
    await _pumpCard(tester, [
      _alert(contents: [_content(id: 'c-1', title: 'Peint tout de suite')]),
    ]);

    await tester.tap(find.text('Peint tout de suite'));
    await tester.pump(); // 1 frame : la navigation construit la destination.

    expect(find.text('Peint tout de suite'), findsOneWidget);
    expect(find.text('CHARGEMENT'), findsNothing);
  });

  testWidgets('une alerte sujet ouvre un article, jamais une liste vide',
      (tester) async {
    final nav = await _pumpCard(tester, [
      _alert(
        kind: AlertKind.topic,
        id: 'topic-profile-uuid',
        name: 'Ligue 1',
        contents: [
          _content(id: 'c-7', title: 'Ligue 1 : le résumé', sourceName: 'L\'Équipe'),
        ],
      ),
    ]);

    await tester.tap(find.text('Ligue 1 : le résumé'));
    await tester.pumpAndSettle();

    expect(nav.location, '/flux-continu/content/c-7');
    expect(nav.location, isNot(contains('source%3A')));
    expect(nav.location, isNot(contains('topic-profile-uuid')));
  });

  testWidgets('la ligne montre le média qui a publié, pas la cible de la cloche',
      (tester) async {
    await _pumpCard(tester, [
      _alert(
        kind: AlertKind.topic,
        name: 'Ligue 1',
        contents: [_content(sourceName: 'Ouest-France')],
      ),
    ]);

    // La méta explique pourquoi la ligne est là (le sujet), et le titre reste
    // l'information principale.
    expect(find.textContaining('Ligue 1'), findsOneWidget);
  });

  testWidgets('sans contenu (backend v1), la carte garde la ligne « N nouveaux »',
      (tester) async {
    final nav = await _pumpCard(tester, [
      _alert(name: 'Le Mensuel', newContent: 3),
    ]);

    expect(find.text('3 nouveaux'), findsOneWidget);
    await tester.tap(find.text('Le Mensuel'));
    await tester.pumpAndSettle();
    expect(nav.location, contains('/flux-continu/source/'));
  });

  testWidgets('sans contenu, une alerte sujet retombe sur « Mes alertes »',
      (tester) async {
    final nav = await _pumpCard(tester, [
      _alert(kind: AlertKind.topic, id: 'topic-uuid', name: 'Ligue 1', newContent: 2),
    ]);

    await tester.tap(find.text('Ligue 1'));
    await tester.pumpAndSettle();

    expect(nav.location, RoutePaths.alerts);
    expect(nav.location, isNot(contains('source')));
  });

  testWidgets('aucune cloche à montrer : la carte disparaît', (tester) async {
    await _pumpCard(tester, const <AlertItem>[]);
    expect(find.text('Gérer mes alertes'), findsNothing);
  });

  group('alertFallbackRoute', () {
    test('une alerte topic ne construit jamais une route source:<id>', () {
      final route = alertFallbackRoute(
        _alert(kind: AlertKind.topic, id: 'b7b1-uuid', name: 'Ligue 1'),
      );
      expect(route, RoutePaths.alerts);
      expect(route, isNot(contains('source')));
      expect(route, isNot(contains('b7b1-uuid')));
    });

    test('une alerte source garde la page de la source', () {
      final route = alertFallbackRoute(_alert(id: 'src-9'));
      expect(route, '/flux-continu/source/source%3Asrc-9');
    });
  });
}
