import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/screens/flux_continu_screen.dart';
import 'package:facteur/features/flux_continu/utils/section_fit.dart';
import 'package:facteur/features/flux_continu/widgets/triage_stack_skeleton.dart';
import 'package:facteur/shared/widgets/loaders/facteur_bike_loader.dart';

/// Garde-fou du squelette « Ton Essentiel ». Le bug : l'ancien placeholder était
/// un bloc plat de 260 px, bien plus court que la carte de tri réelle → carte
/// rognée pendant le chargement puis saut de layout à l'hydratation. Ce test
/// verrouille la géométrie (hauteur réaliste, shimmer présent).
///
/// `_HeroSkeleton` est privé ; `essentielHeroSkeletonForTest()` l'expose
/// (`@visibleForTesting`). Monter `FluxContinuScreen` entier n'est pas jouable
/// (Supabase/Hive/GoRouter), comme pour `firstPreparingSectionIndex`.
void main() {
  // Conservé entre le pump et les assertions : `_HeroSkeleton` est privé, donc
  // `find.byType` lui est inaccessible — `find.byWidget` sur l'instance rendue
  // est le seul moyen de mesurer la carte **entière** (et non un sous-arbre).
  late Widget skeleton;

  Future<void> pumpSkeleton(WidgetTester tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    skeleton = essentielHeroSkeletonForTest();
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(child: skeleton),
        ),
      ),
    );
  }

  testWidgets('respire en shimmer (état « se prépare », pas une carte nue)',
      (tester) async {
    await pumpSkeleton(tester);
    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets('montre le facteur en route plutôt qu\'un en-tête gris',
      (tester) async {
    await pumpSkeleton(tester);

    // Le reproche utilisateur sur le cold boot était « un écran blanc » : à
    // l'ancien contraste, l'en-tête shimmer ne se distinguait pas de la carte.
    // L'attente doit maintenant porter une illustration et un texte.
    expect(find.byType(FacteurBikeLoader), findsOneWidget);
    expect(find.text('Ta tournée arrive'), findsOneWidget);
  });

  testWidgets('réserve la géométrie de la carte de tri, bien au-delà de 260 px',
      (tester) async {
    await pumpSkeleton(tester);

    // La seule carte silhouette, au nouveau format éditorial (grande image),
    // dépasse déjà l'ancien bloc plat de 260 px.
    expect(kTriageCardHeight, greaterThan(260));

    // La carte rendue (en-tête + pile de 2 cartes + barre d'actions) dépasse
    // encore une carte silhouette : plus de tranche rognée. Mesurée sur la
    // carte entière — la mesurer sur le `Shimmer` ne couvrirait plus que la
    // pile depuis que l'en-tête porte le facteur au lieu d'un sweep.
    final rendered = tester.getSize(find.byWidget(skeleton)).height;
    expect(rendered, greaterThan(kTriageCardHeight));
  });

  testWidgets('délègue sa pile à la silhouette partagée', (tester) async {
    await pumpSkeleton(tester);

    // Une seule définition de la silhouette, partagée avec l'attente rendue
    // **dans** `EssentielHiFiCard` : les deux attentes ne peuvent pas diverger
    // de la vraie pile.
    expect(find.byType(TriageStackSkeleton), findsOneWidget);
  });

  group('TriageStackSkeleton', () {
    Future<void> pump(WidgetTester tester, {bool standalone = true}) async {
      tester.view.physicalSize = const Size(390, 844);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(
            body: SingleChildScrollView(
              child: TriageStackSkeleton(standalone: standalone),
            ),
          ),
        ),
      );
    }

    testWidgets('porte son propre shimmer en mode standalone', (tester) async {
      await pump(tester);
      expect(find.byType(Shimmer), findsOneWidget);
    });

    testWidgets('n\'ajoute pas de shimmer quand un ancêtre en fournit un',
        (tester) async {
      await pump(tester, standalone: false);
      expect(find.byType(Shimmer), findsNothing);
    });

    testWidgets(
        'porte le même ordre que la vraie pile : barre de progression puis '
        'contrôle d\'objectif, SOUS la barre d\'actions', (tester) async {
      await pump(tester);

      // Ronds d'action (44 px) → segments de progression (4 px) → contrôle
      // d'objectif (ronds de 26 + phrase de 150×11) : si la silhouette gardait
      // un autre ordre, la mise en page sauterait à l'hydratation — c'est
      // précisément ce qu'elle existe pour empêcher.
      final boxes = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(TriageStackSkeleton),
            matching: find.byType(Container),
          ))
          .map((w) => tester.getRect(find.byWidget(w)))
          .toList();
      final actionBottom = boxes
          .where((r) => r.height == kTriageActionButtonSize)
          .map((r) => r.bottom)
          .reduce((a, b) => a > b ? a : b);
      final progressTop = boxes
          .where((r) => r.height == kTriageProgressSegmentHeight)
          .map((r) => r.top)
          .reduce((a, b) => a < b ? a : b);
      final controlTop = boxes
          // Les deux moitiés de la phrase du contrôle (« Garder » puis
          // « articles ») — la barre de méta de la carte fait aussi
          // 11 de haut, mais 96 de large.
          .where((r) => r.height == 11 && r.width != 96)
          .map((r) => r.top)
          .reduce((a, b) => a < b ? a : b);
      expect(progressTop, greaterThan(actionBottom));
      expect(controlTop, greaterThan(progressTop));
    });

    testWidgets('réserve la borne haute de hauteur de carte', (tester) async {
      await pump(tester);
      final stack = tester.getSize(find.byType(TriageStackSkeleton)).height;
      expect(stack, greaterThan(kTriageCardHeight));
      expect(
        stack,
        kTriageCardHeight +
            kTriageActionBarHeight +
            kTriageProgressBarHeight +
            kTriageTargetControlHeight,
      );
    });

    testWidgets(
        'annonce la VRAIE barre d\'actions : 2 ronds de 44 + 1 pilule '
        'extensible, et plus aucune barre de compteur', (tester) async {
      await pump(tester);

      // L'ancienne silhouette (3 pastilles de 52 centrées) annonçait une barre
      // qui n'existe pas : l'attente ne ressemblait pas au contenu.
      final bars = tester
          .widgetList<Container>(find.descendant(
            of: find.byType(TriageStackSkeleton),
            matching: find.byType(Container),
          ))
          .toList();
      final actionBarBoxes = [
        for (final b in bars)
          if (tester.getSize(find.byWidget(b)).height == 44)
            tester.getSize(find.byWidget(b)),
      ];
      expect(actionBarBoxes.length, 3);
      expect(actionBarBoxes.where((s) => s.width == 44).length, 2);
      // La pilule prend tout le reste de la largeur.
      expect(actionBarBoxes.where((s) => s.width > 44).length, 1);

      // La colonne réserve exactement carte + actions + barre de progression +
      // contrôle d'objectif : aucun pixel de plus, aucun de moins.
      expect(
        tester.getSize(find.byType(TriageStackSkeleton)).height,
        kTriageCardHeight +
            kTriageActionBarHeight +
            kTriageProgressBarHeight +
            kTriageTargetControlHeight,
      );
    });
  });
}
