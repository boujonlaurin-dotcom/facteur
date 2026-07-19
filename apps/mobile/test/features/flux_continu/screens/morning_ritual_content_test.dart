import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/screens/morning_ritual_screen.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shimmer/shimmer.dart';

/// [MorningRitualContent] est **provider-free** : chaque slide du carrousel se
/// limite à **l'enveloppe seule** (le titre daté + sous-titre ont migré vers
/// l'en-tête [_RitualGreeting], l'ouverture passe par le bouton « Ouvrir ta
/// tournée »). [SectionDeepDiveList] (liste « Ou accède directement à ») est
/// également provider-free et testée ici via des sections fabriquées.
Widget _wrap(Widget child) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(body: child),
  );
}

/// Surface verticale généreuse : évite un overflow dans la surface test par
/// défaut (800×600).
void _useTallSurface(WidgetTester tester) {
  tester.view.physicalSize = const Size(600, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

EssentielArticle _hero(String title) => EssentielArticle(
      contentId: title,
      title: title,
      url: 'https://x/$title',
      publishedAt: DateTime(2026, 1, 1),
      sourceName: 'S',
      sourceLetter: 'S',
      sectionLabel: 'Tech',
      rank: 1,
    );

FeedThemeSection _theme(String slug, String label, int count) => FeedThemeSection(
      kind: SectionKind.theme,
      label: label,
      accent: const Color(0xFF1565C0),
      coreVisibleCount: 5,
      themeSlug: slug,
      items: List.generate(
        count,
        (i) => Content(
          id: '$slug-$i',
          title: 't$i',
          url: 'https://x/$slug/$i',
          contentType: ContentType.article,
          publishedAt: DateTime(2026, 1, 1),
          source: Source(id: 's', name: 'S', type: SourceType.article),
        ),
      ),
    );

/// Coquille de section (échafaudage du reveal rapide) : `isPlaceholder: true`,
/// zéro article. [_SectionRow] doit shimmer sa ligne méta.
FeedThemeSection _placeholderTheme(String slug, String label) =>
    FeedThemeSection(
      kind: SectionKind.theme,
      label: label,
      accent: const Color(0xFF1565C0),
      coreVisibleCount: 5,
      themeSlug: slug,
      items: const <Content>[],
      hasMore: false,
      isPlaceholder: true,
    );

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  group('MorningRitualContent', () {
    testWidgets('slide = enveloppe seule, sans « Salut, » ni sous-titre daté '
        'ni spinner', (
      tester,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(
        const MorningRitualContent(
          reduceMotion: true,
          onOpen: _noop,
        ),
      ));

      // Le « Salut, » est devenu le titre daté de la page (hors slide).
      expect(find.text('Salut,'), findsNothing);
      // Le sous-titre daté par slide a été retiré (slide = enveloppe seule).
      expect(find.textContaining('Ton essentiel du'), findsNothing);
      // Le résumé des manchettes a quitté la carte.
      expect(find.text('À la une ce matin.'), findsNothing);
      // Promesse « no loading » : jamais de spinner au repos.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // L'enveloppe (unique SvgPicture du corps) reste présente.
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('slide = enveloppe seule, sans indice/Serein/manchettes', (
      tester,
    ) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(
        const MorningRitualContent(
          reduceMotion: true,
          onOpen: _noop,
        ),
      ));
      await tester.pump();

      // L'ancien indice « glisse vers le haut » a disparu (swipe-up retiré).
      expect(find.text('Glisse vers le haut'), findsNothing);
      expect(find.text('Mode Serein'), findsNothing);
      // L'enveloppe (unique SvgPicture du corps) reste présente.
      expect(find.byType(SvgPicture), findsOneWidget);
    });

    testWidgets('tient dans la fente carrousel (390×190) sans overflow', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(_wrap(
        const Center(
          child: SizedBox(
            width: 390,
            height: 190, // = _EditionCarouselState._kPageHeight
            child: MorningRitualContent(
              reduceMotion: true,
              onOpen: _noop,
            ),
          ),
        ),
      ));
      // Un overflow RenderFlex ferait échouer le pump (exception capturée).
      expect(tester.takeException(), isNull);
    });

    testWidgets('tap sur l\'enveloppe déclenche l\'ouverture', (tester) async {
      _useTallSurface(tester);
      var opened = 0;
      await tester.pumpWidget(_wrap(
        MorningRitualContent(
          reduceMotion: true,
          onOpen: () => opened++,
        ),
      ));

      // Le GestureDetector est un ancêtre du SvgPicture → warnIfMissed superflu.
      await tester.tap(find.byType(SvgPicture), warnIfMissed: false);
      await tester.pump(const Duration(milliseconds: 400)); // laisse le « pop »
      expect(opened, 1);
    });
  });

  group('SectionDeepDiveList', () {
    testWidgets('une ligne par section : label + compteur + emoji + badge', (
      tester,
    ) async {
      _useTallSurface(tester);
      final essentiel = EssentielSection(
        articles: List.generate(6, (i) => _hero('h$i')),
      );
      await tester.pumpWidget(_wrap(
        SectionDeepDiveList(
          sections: [
            essentiel,
            _theme('tech', 'Technologie', 4),
            _theme('science', 'Sciences', 1),
          ],
          onOpenSection: (_) {},
          onTapManage: () {},
        ),
      ));

      // Divider maquette + lien discret « Gérer » (config Essentiel) à droite.
      expect(find.text('Ou accède directement à'), findsOneWidget);
      expect(find.text('Gérer'), findsOneWidget);

      // Essentiel : « N titres » (uppercased), emoji éditorial.
      expect(find.text(essentiel.label), findsOneWidget);
      expect(find.text('6 TITRES'), findsOneWidget);
      expect(find.text('📰'), findsOneWidget);

      // Thème : « N articles », emoji dédié.
      expect(find.text('Technologie'), findsOneWidget);
      expect(find.text('4 ARTICLES'), findsOneWidget);
      expect(find.text('💻'), findsOneWidget);

      // Section maigre (≤1) → compteur singulier + badge « Peu d'articles ».
      expect(find.text('Sciences'), findsOneWidget);
      expect(find.text('1 ARTICLE'), findsOneWidget);
      expect(find.text('Peu d\'articles'), findsOneWidget);
    });

    testWidgets('tap sur une ligne → onOpenSection(sectionKey)', (tester) async {
      _useTallSurface(tester);
      final tech = _theme('tech', 'Technologie', 4);
      String? tapped;
      await tester.pumpWidget(_wrap(
        SectionDeepDiveList(
          sections: [tech],
          onOpenSection: (key) => tapped = key,
          onTapManage: () {},
        ),
      ));

      await tester.tap(find.text('Technologie'));
      await tester.pump();
      expect(tapped, sectionKey(tech));
      expect(tapped, 'theme:tech');
    });

    testWidgets(
        'section placeholder → label + emoji + shimmer, sans compteur ni flèche',
        (tester) async {
      _useTallSurface(tester);
      await tester.pumpWidget(_wrap(
        SectionDeepDiveList(
          sections: [_placeholderTheme('tech', 'Technologie')],
          onOpenSection: (_) {},
          onTapManage: () {},
        ),
      ));
      // Un seul pump : le shimmer anime en boucle (pas de pumpAndSettle).
      await tester.pump();

      // Le label + l'emoji restent lisibles (section « de base » de l'édition).
      expect(find.text('Technologie'), findsOneWidget);
      expect(find.text('💻'), findsOneWidget);
      // Pas de compteur trompeur ni de badge tant que la section charge.
      expect(find.textContaining('ARTICLE'), findsNothing);
      expect(find.text('Peu d\'articles'), findsNothing);
      // La flèche est masquée (remplacée par un espace réservé).
      expect(find.byIcon(Icons.arrow_forward_rounded), findsNothing);
      // Un shimmer discret remplace la ligne méta « N articles ».
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('tap sur le lien discret « Gérer » → onTapManage',
        (tester) async {
      _useTallSurface(tester);
      var managed = 0;
      await tester.pumpWidget(_wrap(
        SectionDeepDiveList(
          sections: [_theme('tech', 'Technologie', 4)],
          onOpenSection: (_) {},
          onTapManage: () => managed++,
        ),
      ));

      await tester.tap(find.text('Gérer'));
      await tester.pump();
      expect(managed, 1);
    });
  });
}

/// Callback inerte `const` pour les cas où l'ouverture n'est pas exercée (permet
/// d'instancier `MorningRitualContent` en `const`).
void _noop() {}
