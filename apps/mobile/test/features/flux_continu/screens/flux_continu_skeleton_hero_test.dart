import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/screens/flux_continu_screen.dart';
import 'package:facteur/shared/widgets/loaders/facteur_bike_loader.dart';

/// Contrat B0/C1 du squelette de cold boot (lot cold-start-load-order) :
///
///  - **B0** — quand l'écran lui fournit un `hero` (la vraie carte « Ton
///    Essentiel », hydratée dès la résolution de `/api/essentiel`), le
///    squelette le rend À LA PLACE du placeholder statique — le premier contenu
///    réel n'attend plus la Phase 1 ;
///  - **C1** — le squelette est scrollable (clamping, pas de snap) et accepte
///    le contrôleur partagé, pour que le flip Phase 1 conserve l'offset d'un
///    « rusher » qui descend sans trier.
///
/// `_FluxContinuSkeleton` est privé ; `fluxContinuSkeletonForTest()` l'expose
/// (`@visibleForTesting`) — monter `FluxContinuScreen` entier n'est pas jouable
/// en test (Supabase/Hive/GoRouter), cf. `essentielHeroSkeletonForTest`.
void main() {
  Future<void> pump(
    WidgetTester tester, {
    Widget? hero,
    ScrollController? controller,
  }) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: fluxContinuSkeletonForTest(hero: hero, controller: controller),
        ),
      ),
    );
  }

  testWidgets('sans héros hydraté → placeholder statique (comportement historique)',
      (tester) async {
    await pump(tester);
    expect(find.byType(FacteurBikeLoader), findsOneWidget);
    expect(find.text('Ta tournée arrive'), findsOneWidget);
  });

  testWidgets('B0 — le héros fourni remplace le placeholder statique',
      (tester) async {
    const marker = Key('hydrated-hero');
    await pump(tester, hero: const SizedBox(key: marker, height: 400));

    expect(find.byKey(marker), findsOneWidget);
    // Plus aucun placeholder héros : la vraie carte a pris sa place.
    expect(find.byType(FacteurBikeLoader), findsNothing);
    expect(find.text('Ta tournée arrive'), findsNothing);
  });

  testWidgets('C1 — squelette scrollable (clamping) sur le contrôleur partagé',
      (tester) async {
    final controller = ScrollController();
    addTearDown(controller.dispose);
    // Un héros haut + le padding bas garantissent un extent scrollable.
    await pump(
      tester,
      hero: const SizedBox(height: 1200),
      controller: controller,
    );

    final listView = tester.widget<ListView>(find.byType(ListView));
    expect(listView.physics, isA<ClampingScrollPhysics>(),
        reason: 'le rusher doit pouvoir descendre — plus de '
            'NeverScrollableScrollPhysics');
    expect(listView.controller, same(controller));

    controller.jumpTo(300);
    await tester.pump();
    expect(controller.offset, 300,
        reason: 'l\'offset vit sur le contrôleur partagé → l\'écran peut le '
            'transporter au flip Phase 1');
  });
}
