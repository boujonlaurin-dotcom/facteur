import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/screens/flux_continu_screen.dart';
import 'package:facteur/features/flux_continu/utils/section_fit.dart';
import 'package:facteur/features/flux_continu/widgets/triage_stack_skeleton.dart';

/// Garde-fou du squelette « Ton Essentiel ». Le bug : l'ancien placeholder était
/// un bloc plat de 260 px, bien plus court que la carte de tri réelle → carte
/// rognée pendant le chargement puis saut de layout à l'hydratation. Ce test
/// verrouille la géométrie (hauteur réaliste, shimmer présent).
///
/// `_HeroSkeleton` est privé ; `essentielHeroSkeletonForTest()` l'expose
/// (`@visibleForTesting`). Monter `FluxContinuScreen` entier n'est pas jouable
/// (Supabase/Hive/GoRouter), comme pour `firstPreparingSectionIndex`.
void main() {
  Future<void> pumpSkeleton(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: essentielHeroSkeletonForTest(),
          ),
        ),
      ),
    );
  }

  testWidgets('respire en shimmer (état « se prépare », pas une carte nue)',
      (tester) async {
    await pumpSkeleton(tester);
    expect(find.byType(Shimmer), findsOneWidget);
  });

  testWidgets('réserve la géométrie de la carte de tri, bien au-delà de 260 px',
      (tester) async {
    await pumpSkeleton(tester);

    // La seule carte silhouette, au nouveau format éditorial (grande image),
    // dépasse déjà l'ancien bloc plat de 260 px.
    expect(kTriageCardHeight, greaterThan(260));

    // La carte rendue (en-tête/pastille + pile de 2 cartes + barre d'actions)
    // dépasse encore une carte silhouette : plus de tranche rognée.
    final rendered = tester.getSize(find.byType(Shimmer)).height;
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
        'porte le même ordre que la vraie pile : progression SOUS la barre '
        'd\'actions', (tester) async {
      await pump(tester);

      // Segments d'action (44 px) puis silhouette de progression (barre de
      // texte courte de 11 px, design 2A) : si la silhouette gardait l'ancien
      // ordre, la mise en page sauterait à l'hydratation — c'est précisément
      // ce qu'elle existe pour empêcher.
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
          // 140×11 : la silhouette de progression — la barre de méta de la
          // carte fait aussi 11 de haut, mais 96 de large.
          .where((r) => r.height == 11 && r.width == 140)
          .map((r) => r.top)
          .reduce((a, b) => a < b ? a : b);
      expect(progressTop, greaterThan(actionBottom));
    });

    testWidgets('réserve la borne haute de hauteur de carte', (tester) async {
      await pump(tester);
      final stack = tester.getSize(find.byType(TriageStackSkeleton)).height;
      expect(stack, greaterThan(kTriageCardHeight));
      expect(
        stack,
        kTriageProgressHeight + kTriageCardHeight + kTriageActionBarHeight,
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

      // Plus de barre de compteur : la colonne s'arrête à la barre d'actions.
      expect(
        tester.getSize(find.byType(TriageStackSkeleton)).height,
        kTriageProgressHeight + kTriageCardHeight + kTriageActionBarHeight,
      );
    });
  });
}
