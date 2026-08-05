import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/screens/flux_continu_screen.dart';
import 'package:facteur/features/flux_continu/utils/section_fit.dart';

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

  testWidgets('réserve la hauteur de la carte de tri, bien au-delà de 260 px',
      (tester) async {
    await pumpSkeleton(tester);

    // Hauteur de la seule pile de tri déjà supérieure à l'ancien bloc plat.
    final stackHeight = triageReservedHeight(
      slateSize: 5,
      chromeHeight: 0,
      leadHeight: kHeroLeadHeight,
      mediumHeight: kHeroMediumHeight,
    );
    expect(stackHeight, greaterThan(260));

    // La carte rendue (chrome + en-tête/pastille + pile) dépasse encore la pile,
    // donc largement l'ancien 260 px : plus de tranche rognée.
    final rendered = tester.getSize(find.byType(Shimmer)).height;
    expect(rendered, greaterThan(stackHeight));
  });
}
