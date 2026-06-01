import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:facteur/config/routes.dart';
import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show HighlightSpan, TokenSpan;
import 'package:facteur/features/feed/widgets/diff_title.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';
import 'package:facteur/widgets/design/facteur_card.dart';

/// Garantit qu'un tap sur une carte/ligne de perspective ROUTE vers le reader
/// unique (`ContentDetailScreen` mode externe) via la route nommée
/// `content-external` — et **jamais** vers le navigateur système via
/// `launchUrl`. Le PO veut un seul reader qui évolue dans le temps : la
/// présence d'un `launchUrl(externalApplication)` ici (signalée par un
/// `MissingPluginException` de `url_launcher` en widget test) serait une
/// régression directe.
Perspective _persp(String name, String bias) => Perspective(
      title: 'Titre court avec mot fort',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '$name.example.com',
      biasStance: bias,
      highlightSpans: const [
        HighlightSpan(start: 18, end: 22, text: 'fort', bias: 'left'),
      ],
      sharedTokens: const [TokenSpan(start: 0, end: 5, text: 'Titre')],
    );

/// Capture la `Perspective` reçue par la route `content-external` (au lieu
/// d'instancier le vrai `ContentDetailScreen`, qui dépend de Supabase/Hive et
/// crasherait en widget test). Asserter cette navigation suffit à prouver le
/// contrat de routage.
Perspective? _routedPerspective;

const _kExternalReaderMarker = Key('external-reader-marker');

/// Router de test : la route `content-external` enregistre le tap et rend un
/// marqueur léger ; on évite ainsi le reader réel tout en validant l'appel
/// `pushNamed(RouteNames.contentExternal, extra: Perspective)`.
GoRouter _router(Widget home) {
  return GoRouter(
    initialLocation: '/',
    routes: [
      GoRoute(path: '/', builder: (_, __) => home),
      GoRoute(
        // Utilise la VRAIE constante de path (pas un littéral) pour que ce
        // harness reflète le wiring de production — un path relatif au
        // top-level (régression "Page non trouvée: /content-external")
        // ferait alors échouer ces tests.
        path: RoutePaths.contentExternal,
        name: RouteNames.contentExternal,
        builder: (_, state) {
          _routedPerspective = state.extra as Perspective?;
          return const Scaffold(
            body: SizedBox(key: _kExternalReaderMarker),
          );
        },
      ),
    ],
  );
}

Widget _variantRowHome() {
  return Scaffold(
    body: SingleChildScrollView(
      child: SizedBox(
        width: 390,
        child: PerspectivesInlineSection(
          perspectives: [_persp('Source-Gauche', 'left')],
          biasDistribution: const {'left': 1},
          keywords: const [],
          contentId: 'test',
          externalSelectedSegments: null,
          onSegmentTap: (_) {},
          onClearSegments: () {},
          onToggle: () {},
          isExpanded: true,
          referenceTitle: '',
        ),
      ),
    ),
  );
}

Widget _bottomSheetHome() {
  return Scaffold(
    body: Builder(
      builder: (ctx) => Center(
        child: ElevatedButton(
          onPressed: () => showModalBottomSheet<void>(
            context: ctx,
            isScrollControlled: true,
            backgroundColor: Colors.transparent,
            builder: (_) => PerspectivesBottomSheet(
              perspectives: [_persp('Source-Gauche', 'left')],
              biasDistribution: const {'left': 1},
              keywords: const [],
              contentId: 'test',
            ),
          ),
          child: const Text('open sheet'),
        ),
      ),
    ),
  );
}

Widget _app(Widget home) {
  return ProviderScope(
    child: MaterialApp.router(
      theme: FacteurTheme.lightTheme,
      routerConfig: _router(home),
    ),
  );
}

void main() {
  // Garde-fou direct contre la régression "Page non trouvée:
  // /content-external" : une GoRoute top-level DOIT avoir un path absolu
  // (commençant par '/'), sinon go_router ne sait pas résoudre la route nommée.
  test('content-external : route top-level avec path absolu résolvable', () {
    expect(RoutePaths.contentExternal.startsWith('/'), isTrue,
        reason: 'Une GoRoute top-level doit avoir un path absolu.');
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (_, __) => const SizedBox()),
        GoRoute(
          path: RoutePaths.contentExternal,
          name: RouteNames.contentExternal,
          builder: (_, __) => const SizedBox(),
        ),
      ],
    );
    expect(router.namedLocation(RouteNames.contentExternal),
        RoutePaths.contentExternal);
  });

  setUp(() {
    _routedPerspective = null;
    // FacteurCard.onTap await `HapticFeedback.mediumImpact()` avant de
    // déclencher le callback ; sans handler mocké, le future ne se résout
    // jamais en widget test et la navigation ne se déclenche pas.
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  testWidgets(
      '_VariantRow tap → route vers content-external (pas de launchUrl)',
      (tester) async {
    await tester.pumpWidget(_app(_variantRowHome()));
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.byKey(_kExternalReaderMarker), findsNothing,
        reason: 'Le reader ne doit pas être présent avant le tap.');

    // Tape sur le DiffTitle (le titre est rendu via RichText, pas Text).
    final tappable = find.byType(DiffTitle);
    expect(tappable, findsWidgets);
    await tester.tap(tappable.first, warnIfMissed: false);
    await tester.pumpAndSettle(const Duration(milliseconds: 400));

    expect(find.byKey(_kExternalReaderMarker), findsOneWidget,
        reason:
            'Le tap doit router vers ContentDetailScreen (mode externe) via '
            'pushNamed(RouteNames.contentExternal) — pas launchUrl.');
    expect(_routedPerspective?.url, 'https://example.com/Source-Gauche',
        reason: 'La Perspective tapée doit être transmise via extra.');
  });

  testWidgets(
      '_PerspectiveCard tap → route vers content-external (pas de launchUrl)',
      (tester) async {
    await tester.pumpWidget(_app(_bottomSheetHome()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open sheet'));
    await tester.pumpAndSettle();

    expect(find.byType(PerspectivesBottomSheet), findsOneWidget);
    expect(find.byKey(_kExternalReaderMarker), findsNothing);

    // Tape sur la zone titre de la FacteurCard. Le footer interne a un
    // `GestureDetector` opaque (pour le source detail modal) qui absorbe les
    // taps même quand son onTap est null — donc on cible une position en
    // haut de la carte, dans la région du DiffTitle.
    final card = find.byType(FacteurCard);
    expect(card, findsOneWidget);
    final cardRect = tester.getRect(card);
    await tester.tapAt(Offset(cardRect.center.dx, cardRect.top + 24));
    await tester.pumpAndSettle(const Duration(milliseconds: 600));

    expect(find.byKey(_kExternalReaderMarker), findsOneWidget,
        reason: 'Le tap sur _PerspectiveCard doit router vers '
            'ContentDetailScreen (mode externe) via pushNamed.');
    expect(_routedPerspective?.url, 'https://example.com/Source-Gauche');
  });
}
