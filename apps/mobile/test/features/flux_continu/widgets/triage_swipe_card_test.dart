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
  final VoidCallback? onTap;

  const _Harness({
    required this.ids,
    required this.onDecision,
    this.onGestureProgress,
    this.onTap,
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
      // Plus de `height` : la carte prend celle de son enfant (reprise PO
      // 08/08). C'est le `SizedBox` du child ci-dessous qui la dimensionne.
      onGestureProgress: widget.onGestureProgress,
      onTap: widget.onTap,
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

  // ── Tap (Story 33.2 : la carte ouvre l'article) ───────────────────────────

  testWidgets('un tap appelle onTap sans déclencher AUCUNE décision',
      (tester) async {
    final taps = <String>[];
    final decisions = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: Center(
            child: TriageSwipeCard(
              articleId: 'a',
              onTap: () => taps.add('a'),
              onKeep: () => decisions.add('keep'),
              onPass: () => decisions.add('pass'),
              child: const SizedBox(height: 300, child: Text('card-a')),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('card-a'));
    await tester.pumpAndSettle();

    expect(taps, ['a']);
    expect(decisions, isEmpty,
        reason: 'le tap ouvre, il ne garde pas — la décision vient au retour');
  });

  testWidgets(
      'avec onTap branché, un drag au-delà du seuil décide toujours '
      '(non-régression de l\'arène tap × drag)', (tester) async {
    final taps = <int>[];
    final decisions = await pumpHarness(tester);
    // Reconstruit le harnais avec onTap : on passe par un widget dédié pour ne
    // pas dupliquer la mécanique — ici on vérifie surtout que le drag gagne.
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: Center(
            child: _Harness(
              ids: const ['a', 'b'],
              onDecision: decisions.add,
              onTap: () => taps.add(1),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pumpAndSettle();

    expect(decisions, ['keep-a']);
    expect(taps, isEmpty, reason: 'un drag n\'est pas un tap');
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

  // ── Filet « geste sans fin détectée » (Listener passif) ───────────────────
  //
  // Le `HorizontalDragGestureRecognizer` peut ne jamais délivrer de
  // `onEnd`/`onCancel` terminal (2ᵉ doigt qui atterrit en cours de swipe,
  // perte de route d'arène) : la carte restait alors figée translatée, pour
  // toujours (aucune décision ⇒ l'index n'avance pas ⇒ jamais de reset).
  // L'invariant testé ici : **quelle que soit la séquence de pointeurs, un
  // drag suivant décide toujours** — et le filet ne se déclenche jamais sur
  // un geste proprement terminé (compteur à zéro).

  testWidgets(
      'multi-touch, lever entrelacé : la carte ne se fige jamais, un drag '
      'suivant décide toujours (invariant du filet)', (tester) async {
    final decisions = await pumpHarness(tester);
    final center = tester.getCenter(find.byType(TriageSwipeCard));

    // 1ᵉʳ doigt : drag en cours (150 px, sous le seuil de 200).
    final g1 = await tester.startGesture(center, pointer: 1);
    await g1.moveBy(const Offset(150, 0));
    await tester.pump();
    // 2ᵉ doigt qui atterrit en plein swipe, puis lever entrelacé.
    final g2 = await tester.startGesture(center.translate(30, 20), pointer: 2);
    await tester.pump();
    await g1.up();
    await tester.pump();
    await g2.up();
    await tester.pumpAndSettle();

    // Sous le seuil et sans vélocité : aucune décision ne doit être tombée.
    expect(decisions, isEmpty);
    expect(find.text('card-a'), findsOneWidget);
    expect(stamps(), findsNothing, reason: 'extent revenu à zéro');

    // L'invariant : la carte décide toujours au geste suivant, pas de gel.
    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pumpAndSettle();
    expect(decisions, ['keep-a']);
    expect(find.text('card-b'), findsOneWidget);
  });

  testWidgets(
      'drag abandonné + changement d\'article : état nettoyé, aucun timer ni '
      'microtask ne fuit sur la carte suivante', (tester) async {
    String id = 'a';
    late StateSetter setId;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(extensions: [FacteurPalettes.light]),
        home: Scaffold(
          body: Center(
            child: StatefulBuilder(
              builder: (context, setState) {
                setId = setState;
                return TriageSwipeCard(
                  articleId: id,
                  onKeep: () {},
                  onPass: () {},
                  child: SizedBox(height: 300, child: Text('card-$id')),
                );
              },
            ),
          ),
        ),
      ),
    );

    // Geste vif, jamais terminé (pas de `.up()` avant le changement de carte).
    final g = await tester
        .startGesture(tester.getCenter(find.byType(TriageSwipeCard)));
    await g.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(find.text('JE GARDE'), findsOneWidget);

    // La carte change d'article sous le geste (teardown didUpdateWidget).
    setId(() => id = 'b');
    await tester.pump();

    // Carte fraîche : extent nettoyé, aucun tampon hérité.
    expect(find.text('card-b'), findsOneWidget);
    expect(stamps(), findsNothing);

    // Le doigt se lève après coup : le filet ne doit PAS réconcilier un geste
    // qui appartenait à la carte précédente.
    await g.up();
    await tester.pumpAndSettle();
    final state =
        tester.state<TriageSwipeCardState>(find.byType(TriageSwipeCard));
    expect(state.lostGestureResolutions, 0);
    expect(stamps(), findsNothing);
  });

  testWidgets(
      'PointerCancel au binding : spring-back, aucune décision, la carte '
      'reste re-swipeable', (tester) async {
    final decisions = await pumpHarness(tester);

    final g = await tester
        .startGesture(tester.getCenter(find.byType(TriageSwipeCard)));
    await g.moveBy(const Offset(150, 0));
    await tester.pump();
    await g.cancel();
    await tester.pumpAndSettle();

    expect(decisions, isEmpty);
    expect(find.text('card-a'), findsOneWidget);
    expect(stamps(), findsNothing);

    await tester.drag(find.byType(TriageSwipeCard), swipeRight);
    await tester.pumpAndSettle();
    expect(decisions, ['keep-a']);
    expect(find.text('card-b'), findsOneWidget);
  });

  testWidgets(
      'filet passif : compteur à zéro sur tous les drags propres '
      '(down + move + up bruts au binding)', (tester) async {
    final decisions = await pumpHarness(tester);
    final center = tester.getCenter(find.byType(TriageSwipeCard));
    final state =
        tester.state<TriageSwipeCardState>(find.byType(TriageSwipeCard));

    // Séquence brute au binding — le chemin que le Listener observe. Les
    // déplacements sont fractionnés : le delta accumulé avant l'acceptation
    // d'arène est ignoré (`DragStartBehavior.start`), un unique gros move ne
    // ferait donc jamais franchir le seuil à `_dragExtent`.
    tester.binding.handlePointerEvent(
      PointerDownEvent(pointer: 7, position: center),
    );
    for (var i = 1; i <= 5; i++) {
      tester.binding.handlePointerEvent(
        PointerMoveEvent(
          pointer: 7,
          position: center + Offset(60.0 * i, 0),
          delta: const Offset(60, 0),
        ),
      );
      await tester.pump();
    }
    tester.binding.handlePointerEvent(
      PointerUpEvent(pointer: 7, position: center + const Offset(300, 0)),
    );
    await tester.pumpAndSettle();

    // Le recognizer a terminé proprement : la décision est tombée par le
    // chemin normal et le filet n'a rien eu à réconcilier.
    expect(decisions, ['keep-a']);
    expect(state.lostGestureResolutions, 0);

    // Les drags synthétiques propres non plus ne le déclenchent jamais.
    await tester.drag(find.byType(TriageSwipeCard), swipeLeft);
    await tester.pumpAndSettle();
    expect(decisions, ['keep-a', 'pass-b']);
    expect(state.lostGestureResolutions, 0);
  });

  // ── Progression du geste (promotion de la carte du dessous) ────────────────

  testWidgets(
      'onGestureProgress monte pendant la sortie puis repart de zéro sur la '
      'carte suivante', (tester) async {
    final progress = <double>[];
    await pumpHarness(tester, onGestureProgress: progress.add);
    await tester.pump();

    // Au repos : **rien n'est émis du tout**. L'avancée part des points qui
    // mutent le geste, jamais de `build` — sinon une carte immobile allouait une
    // closure et un post-frame callback à chaque frame, pour une valeur qui ne
    // bougeait pas.
    expect(progress.where((p) => p != 0), isEmpty);

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
