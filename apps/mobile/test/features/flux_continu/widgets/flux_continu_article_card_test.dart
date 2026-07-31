import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/flux_continu/widgets/coverage_chip.dart';
import 'package:facteur/features/flux_continu/widgets/flux_continu_article_card.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/widgets/design/facteur_thumbnail.dart';
import 'package:timeago/timeago.dart' as timeago;
import 'package:visibility_detector/visibility_detector.dart';

import 'package:facteur/core/utils/fr_compact_messages.dart';

Content _content({
  String? sourceTheme,
  String sourceName = 'Le Monde',
  DateTime? publishedAt,
}) =>
    Content(
      id: 'c-1',
      title: 'Titre article Flux',
      url: 'https://example.com/1',
      // Pas de thumbnail : la carte reste text-only, donc la seule
      // FacteurThumbnail éventuelle vient de l'aperçu flottant.
      description: 'Un chapô pour l\'aperçu.',
      contentType: ContentType.article,
      publishedAt: publishedAt ?? DateTime(2026, 7, 10),
      // Pas de topics ML → `progressionTopic` retombe sur le thème source, le
      // fallback qui garde une pastille utile quand la classif est en retard.
      source: Source(
        id: 's-1',
        name: sourceName,
        type: SourceType.article,
        theme: sourceTheme,
      ),
    );

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        displayModeSpecProvider.overrideWith((ref) => DisplayModeSpec.normal),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    // Sans ça `timeago` retombe sur l'anglais long (« 3 months ago ») et le
    // footer mesuré n'a plus rien à voir avec celui de l'app (« 2 h »).
    timeago.setLocaleMessages('fr_short', FrCompactMessages());
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  testWidgets(
      'long-press reopens the floating preview overlay + fires the '
      'conversion hook (régression #973)', (tester) async {
    var conversions = 0;
    await tester.pumpWidget(_wrap(
      FluxContinuArticleCard(
        article: _content(),
        onTap: () {},
        onLongPressConversion: () => conversions++,
      ),
    ));

    expect(find.byType(FacteurThumbnail), findsNothing);

    final gesture = await tester
        .startGesture(tester.getCenter(find.text('Titre article Flux')));
    await tester.pump(const Duration(milliseconds: 600)); // deadline
    await tester.pump(const Duration(milliseconds: 200)); // anim overlay

    // Le vrai aperçu est de retour (PR #973 l'avait remplacé par un pulse).
    expect(find.byType(FacteurThumbnail), findsOneWidget,
        reason: 'Long-press must reopen the floating preview overlay.');
    // Le hook analytics du long-press réel reste appelé.
    expect(conversions, 1);

    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.byType(FacteurThumbnail), findsNothing);
  });

  testWidgets('footer shows the coverage chip when the subject is covered by '
      'several newsrooms', (tester) async {
    await tester.pumpWidget(_wrap(
      FluxContinuArticleCard(
        article: _content(),
        sourceCount: 3,
        perspectiveSources: const [
          SourceMini(name: 'Le Monde'),
          SourceMini(name: 'Libération'),
          SourceMini(name: 'Le Figaro'),
        ],
      ),
    ));

    expect(find.byKey(const Key('flux-coverage-chip')), findsOneWidget);
    expect(find.text('3 sources'), findsOneWidget);
  });

  testWidgets('no coverage chip below the 2-source threshold', (tester) async {
    await tester.pumpWidget(_wrap(
      FluxContinuArticleCard(
        article: _content(),
        sourceCount: 1,
        perspectiveSources: const [SourceMini(name: 'Le Monde')],
      ),
    ));

    expect(find.byKey(const Key('flux-coverage-chip')), findsNothing);
  });

  testWidgets('coverage chip caps the avatar stack at 3', (tester) async {
    await tester.pumpWidget(_wrap(
      FluxContinuArticleCard(
        article: _content(),
        sourceCount: 6,
        perspectiveSources: const [
          SourceMini(name: 'A'),
          SourceMini(name: 'B'),
          SourceMini(name: 'C'),
          SourceMini(name: 'D'),
          SourceMini(name: 'E'),
          SourceMini(name: 'F'),
        ],
      ),
    ));

    // Les avatars de la pile + le point d'identité de la source de la carte.
    expect(find.byType(SourceDot), findsNWidgets(4));
    expect(find.text('6 sources'), findsOneWidget);
  });

  testWidgets('footer no longer renders a sub-theme pill', (tester) async {
    await tester.pumpWidget(_wrap(
      FluxContinuArticleCard(article: _content(sourceTheme: 'tech')),
    ));

    expect(find.text('Tech & Innovation'), findsNothing);
  });

  testWidgets(
      'footer tient en 390 px avec un nom de source long, la puce de '
      'couverture et le badge de divergence (budget horizontal)',
      (tester) async {
    // Le viewport mobile de référence du design system. Un dépassement de la
    // Row du footer lèverait une FlutterError « RenderFlex overflowed » que
    // le framework de test remonte via takeException.
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_wrap(
      FluxContinuArticleCard(
        article: _content(
          sourceName: 'Le Monde Diplomatique',
          publishedAt: DateTime.now().subtract(const Duration(hours: 2)),
        ),
        sourceCount: 3,
        divergenceLevel: 'high',
        perspectiveSources: const [
          SourceMini(name: 'Le Monde'),
          SourceMini(name: 'Libération'),
          SourceMini(name: 'Le Figaro'),
        ],
      ),
    ));

    // Un dépassement lèverait « RenderFlex overflowed » ; c'est le nom de
    // source qui doit céder en premier (ellipse), jamais la puce.
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('flux-coverage-chip')), findsOneWidget);
    expect(find.text('3 sources'), findsOneWidget);
  });
}
