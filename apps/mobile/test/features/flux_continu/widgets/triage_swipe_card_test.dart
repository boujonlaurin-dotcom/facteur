import 'package:facteur/config/theme.dart';
import 'package:facteur/features/flux_continu/widgets/triage_swipe_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Régression du bug prioritaire de l'itération PO 33.1 : « le swipe se fige,
/// carte grisée, débloquée seulement via Je garde ». Ce banc exerce la carte de
/// tri **en isolation**, avec un harnais qui reproduit la réutilisation d'un
/// unique `TriageSwipeCardState` (via `GlobalKey`) pour tous les articles — la
/// racine du bug. On vérifie que **chaque** décision fait avancer, qu'aucun
/// geste ne fige la carte, et (implicitement, par l'absence de « Timer still
/// pending ») que le garde-fou d'avancée est bien désarmé au bon moment.

/// Harnais : une seule carte réutilisée (même `GlobalKey`), l'`articleId` change
/// à chaque décision — exactement comme `EssentielTriageStack`.
class _Harness extends StatefulWidget {
  final List<String> ids;
  final void Function(String decision) onDecision;
  final ValueChanged<double>? onGestureProgress;

  const _Harness({
    required this.ids,
    required this.onDecision,
    this.onGestureProgress,
  });

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final GlobalKey<TriageSwipeCardState> _key = GlobalKey();
  int _index = 0;

  void _advance(String decision) {
    widget.onDecision(decision);
    setState(() => _index++);
  }

  @override
  Widget build(BuildContext context) {
    if (_index >= widget.ids.length) return const Text('done');
    final id = widget.ids[_index];
    return TriageSwipeCard(
      key: _key,
      articleId: id,
      height: 300,
      onGestureProgress: widget.onGestureProgress,
      onKeep: () => _advance('keep-$id'),
      onPass: () => _advance('pass-$id'),
      child: SizedBox(
        height: 300,
        child: Center(child: Text('card-$id')),
      ),
    );
  }
}

void main() {
  Future<List<String>> pumpHarness(
    WidgetTester tester, {
    List<String> ids = const ['a', 'b', 'c', 'd', 'e'],
    ValueChanged<double>? onGestureProgress,
  }) async {
    final decisions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: Center(
            child: _Harness(
              ids: ids,
              onDecision: decisions.add,
              onGestureProgress: onGestureProgress,
            ),
          ),
        ),
      ),
    );
    return decisions;
  }

  /// Les tampons (« JE GARDE » / « PAS POUR MOI ») sont privés : on les repère
  /// par leur libellé en capitales, qui n'existe nulle part ailleurs.
  Finder stamps() => find.byWidgetPredicate(
        (w) =>
            w is Text &&
            (w.data == 'JE GARDE' || w.data == 'PAS POUR MOI'),
      );

  // Au-delà du seuil (0,25 × largeur ; écran de test 800 → 200 px).
  const Offset swipeRight = Offset(400, 0);
  const Offset swipeLeft = Offset(-400, 0);

  testWidgets('swipe droite → garde et avance à la carte suivante',
      (tester) async {
    final decisions = await pumpHarness(tester);

    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pumpAndSettle();

    expect(decisions, ['keep-a']);
    expect(find.text('card-b'), findsOneWidget);
  });

  testWidgets('swipe gauche → passe et avance', (tester) async {
    final decisions = await pumpHarness(tester);

    await tester.drag(find.byType(TriageSwipeCard), swipeLeft);
    await tester.pumpAndSettle();

    expect(decisions, ['pass-a']);
    expect(find.text('card-b'), findsOneWidget);
  });

  testWidgets(
      'swipes consécutifs rapides : chaque décision avance, aucune carte '
      'ne se fige (régression prioritaire)', (tester) async {
    final decisions = await pumpHarness(tester);

    // Alterne garde/passe sur les 5 cartes, sans jamais rester coincé.
    await tester.drag(find.byType(TriageSwipeCard), swipeRight); // a
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TriageSwipeCard), swipeLeft); // b
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TriageSwipeCard), swipeRight); // c
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TriageSwipeCard), swipeLeft); // d
    await tester.pumpAndSettle();
    await tester.drag(find.byType(TriageSwipeCard), swipeRight); // e
    await tester.pumpAndSettle();

    expect(decisions, [
      'keep-a',
      'pass-b',
      'keep-c',
      'pass-d',
      'keep-e',
    ]);
    // Toutes triées → plus de carte figée hors écran, l'index est allé au bout.
    expect(find.text('done'), findsOneWidget);
  });

  testWidgets(
      'un swipe pendant l\'anim de sortie est ignoré : une seule décision, '
      'un seul pas d\'avance', (tester) async {
    final decisions = await pumpHarness(tester);

    // Déclenche la sortie de la carte a, puis pump UNE frame (anim en cours).
    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pump();

    // Deuxième geste pendant l'anim : `onHorizontalDragStart` court-circuite
    // tant que l'exit anime → aucun effet.
    await tester.drag(find.byType(TriageSwipeCard), swipeLeft);
    await tester.pumpAndSettle();

    expect(decisions, ['keep-a'], reason: 'le 2ᵉ geste ne double pas la décision');
    expect(find.text('card-b'), findsOneWidget);
  });

  testWidgets(
      'un drag sous le seuil ne décide pas et laisse la carte re-swipeable '
      '(chemin de reset)', (tester) async {
    final decisions = await pumpHarness(tester);

    // 120 px < seuil 200 px → pas de décision, la carte revient au centre.
    await tester.drag(find.byType(TriageSwipeCard), const Offset(120, 0));
    await tester.pumpAndSettle();

    expect(decisions, isEmpty);
    expect(find.text('card-a'), findsOneWidget);

    // La carte reste pleinement fonctionnelle : un vrai swipe décide ensuite.
    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pumpAndSettle();

    expect(decisions, ['keep-a']);
    expect(find.text('card-b'), findsOneWidget);
  });

  // ── Tampons ───────────────────────────────────────────────────────────────

  testWidgets('aucun tampon au repos, ni sur une carte fraîchement remplacée',
      (tester) async {
    await pumpHarness(tester);

    // Au repos, `_dragExtent == 0` : rien à annoncer.
    expect(stamps(), findsNothing);

    // Après une décision, la carte suivante arrive vierge. Sans le gate sur un
    // geste réel, un `effectiveDx` résiduel la tamponnait le temps d'une frame
    // et elle se lisait comme « déjà décidée ».
    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pumpAndSettle();

    expect(find.text('card-b'), findsOneWidget);
    expect(stamps(), findsNothing);
  });

  testWidgets('un drag réel pose bien le tampon correspondant', (tester) async {
    await pumpHarness(tester);

    final gesture =
        await tester.startGesture(tester.getCenter(find.text('card-a')));
    await gesture.moveBy(const Offset(90, 0));
    await tester.pump();
    expect(find.text('JE GARDE'), findsOneWidget);
    expect(find.text('PAS POUR MOI'), findsNothing);

    await gesture.moveBy(const Offset(-180, 0));
    await tester.pump();
    expect(find.text('PAS POUR MOI'), findsOneWidget);
    expect(find.text('JE GARDE'), findsNothing);

    await gesture.up();
    await tester.pumpAndSettle();
  });

  // ── Progression du geste (promotion de la carte du dessous) ────────────────

  testWidgets(
      'onGestureProgress monte pendant la sortie puis repart de zéro sur la '
      'carte suivante', (tester) async {
    final progress = <double>[];
    await pumpHarness(tester, onGestureProgress: progress.add);
    await tester.pump();

    // Au repos : rien à promouvoir.
    expect(progress.last, 0);

    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pump();
    expect(progress.reduce((a, b) => a > b ? a : b), greaterThan(0));

    await tester.pumpAndSettle();
    // La sortie parcourt 1,2 écran : la promotion sature à 1 avant la fin.
    expect(progress.reduce((a, b) => a > b ? a : b), 1.0);

    // Carte suivante : la promotion est retombée à 0 (la nouvelle carte du
    // dessous n'a pas encore été touchée).
    expect(find.text('card-b'), findsOneWidget);
    expect(progress.last, 0);
  });
}
