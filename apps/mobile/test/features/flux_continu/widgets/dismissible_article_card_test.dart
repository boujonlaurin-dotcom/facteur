import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:visibility_detector/visibility_detector.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/widgets/feedback_inline.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/flux_continu_provider.dart';
import 'package:facteur/features/flux_continu/widgets/dismissible_article_card.dart';
import 'package:facteur/features/flux_continu/widgets/flux_continu_article_card.dart';
import 'package:facteur/features/settings/models/display_mode_spec.dart';
import 'package:facteur/features/settings/providers/display_mode_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';

/// Parité de geste entre la Tournée/Flâner et les pages dédiées « Tout lire » :
/// swipe droit = lire, swipe gauche = masquer + bandeau de feedback inline.

Content _content() => Content(
      id: 'c-1',
      title: 'Titre article section',
      url: 'https://example.com/1',
      contentType: ContentType.article,
      publishedAt: DateTime(2026, 7, 10),
      source: Source(id: 's-1', name: 'Le Monde', type: SourceType.article),
    );

/// Notifier de test : neutralise les appels réseau (`hideContent`/
/// `unhideContent`) et journalise ce que la carte déclenche.
class _FakeFluxNotifier extends FluxContinuNotifier {
  static final hidden = <String>[];
  static final confirmed = <String>[];
  static final restored = <String>[];

  @override
  Future<FluxContinuState> build() async =>
      const FluxContinuState(isLoading: false, sections: []);

  @override
  Future<void> markHiddenRemote(String contentId) async {
    hidden.add(contentId);
  }

  @override
  void confirmDismiss(String contentId) {
    confirmed.add(contentId);
  }

  @override
  Future<void> undoHide(String contentId) async {
    restored.add(contentId);
  }
}

Widget _wrap(Widget child) => ProviderScope(
      overrides: [
        displayModeSpecProvider.overrideWith((ref) => DisplayModeSpec.normal),
        fluxContinuProvider.overrideWith(_FakeFluxNotifier.new),
      ],
      child: MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(body: SingleChildScrollView(child: child)),
      ),
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
    VisibilityDetectorController.instance.updateInterval = Duration.zero;
  });

  setUp(() {
    _FakeFluxNotifier.hidden.clear();
    _FakeFluxNotifier.confirmed.clear();
    _FakeFluxNotifier.restored.clear();
  });

  testWidgets('swipe droit ouvre l\'article', (tester) async {
    var opened = 0;
    await tester.pumpWidget(_wrap(
      DismissibleArticleCard(
        article: _content(),
        analyticsOrigin: 'section_theme',
        onTap: () => opened++,
      ),
    ));

    await tester.drag(find.text('Titre article section'), const Offset(300, 0));
    await tester.pump();

    expect(opened, 1);
    expect(_FakeFluxNotifier.hidden, isEmpty);
  });

  testWidgets('swipe gauche masque l\'article et affiche le bandeau feedback',
      (tester) async {
    await tester.pumpWidget(_wrap(
      DismissibleArticleCard(
        article: _content(),
        analyticsOrigin: 'section_theme',
        onTap: () {},
      ),
    ));

    await tester.drag(find.text('Titre article section'), const Offset(-300, 0));
    await tester.pumpAndSettle();

    expect(_FakeFluxNotifier.hidden, ['c-1']);
    expect(find.byType(FluxContinuArticleCard), findsNothing);
    expect(find.text('Améliore ton flux'), findsOneWidget);
    // Masquage optimiste : rien n'est purgé du feed tant que le bandeau vit.
    expect(_FakeFluxNotifier.confirmed, isEmpty);
  });

  testWidgets('« Annuler » restaure la carte', (tester) async {
    await tester.pumpWidget(_wrap(
      DismissibleArticleCard(
        article: _content(),
        analyticsOrigin: 'section_theme',
        onTap: () {},
      ),
    ));

    await tester.drag(find.text('Titre article section'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Annuler'));
    await tester.pumpAndSettle();

    expect(_FakeFluxNotifier.restored, ['c-1']);
    expect(find.byType(FluxContinuArticleCard), findsOneWidget);
    expect(find.text('Améliore ton flux'), findsNothing);
  });

  testWidgets('fermer le bandeau purge l\'article du feed', (tester) async {
    await tester.pumpWidget(_wrap(
      DismissibleArticleCard(
        article: _content(),
        analyticsOrigin: 'section_theme',
        onTap: () {},
      ),
    ));

    await tester.drag(find.text('Titre article section'), const Offset(-300, 0));
    await tester.pumpAndSettle();
    // Dernière icône du bandeau = la croix (la 1ʳᵉ est la flèche « Annuler »).
    await tester.tap(
      find
          .descendant(
            of: find.byType(FeedbackInline),
            matching: find.byType(Icon),
          )
          .last,
    );
    await tester.pumpAndSettle();

    expect(_FakeFluxNotifier.confirmed, ['c-1']);
    expect(find.byType(FluxContinuArticleCard), findsNothing);
    expect(find.text('Améliore ton flux'), findsNothing);
  });
}
