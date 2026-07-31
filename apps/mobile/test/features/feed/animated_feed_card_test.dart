import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/widgets/animated_feed_card.dart';
import 'package:facteur/shared/widgets/completion_stamp.dart' show kStampGreen;

/// Epic 30 — le filet vert de la lecture aboutie.
///
/// `AnimatedFeedCard` n'avait **aucune référence** dans `lib/` : le filet
/// n'existait pas à l'écran. Ces tests fixent la distinction état/événement qui
/// justifie son existence.
void main() {
  Widget wrap(Widget child, {bool disableAnimations = false}) => MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: Directionality(
          textDirection: TextDirection.ltr,
          child: Center(child: SizedBox(width: 200, height: 100, child: child)),
        ),
      );

  Finder rule() => find.byWidgetPredicate(
        (w) =>
            w is Container &&
            w.decoration is BoxDecoration &&
            (w.decoration as BoxDecoration).color == kStampGreen,
      );

  testWidgets('rien n\'est ajouté à une carte non aboutie', (tester) async {
    await tester.pumpWidget(
      wrap(const AnimatedFeedCard(isCompleted: false, child: Text('carte'))),
    );

    expect(rule(), findsNothing);
    // Pas de Stack, pas de Semantics : le rendu est strictement inchangé.
    expect(find.byType(Stack), findsNothing);
  });

  testWidgets('animate:false peint le filet dès la première frame',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const AnimatedFeedCard(
          isCompleted: true,
          animate: false,
          child: Text('carte'),
        ),
      ),
    );

    // Aucun `pump` supplémentaire : c'est un état, pas une entrée en scène.
    expect(rule(), findsOneWidget);
    expect(tester.widget<Transform>(find.ancestor(
      of: rule(),
      matching: find.byType(Transform),
    )).transform.getMaxScaleOnAxis(), 1.0);
  });

  testWidgets('la transition false → true est animée (retour d\'article)',
      (tester) async {
    Widget build(bool completed) => wrap(
          AnimatedFeedCard(
            isCompleted: completed,
            animate: false,
            child: const Text('carte'),
          ),
        );

    await tester.pumpWidget(build(false));
    await tester.pumpWidget(build(true));

    // `_startDelayed` attend 220 ms non annulables : on avance explicitement
    // par pas — `pumpAndSettle` masquerait la distinction état/événement.
    await tester.pump(const Duration(milliseconds: 100));
    expect(rule(), findsNothing, reason: 'le filet ne s\'est pas encore levé');

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 160));
    expect(rule(), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
  });

  testWidgets('reduce-motion peint le filet plein immédiatement',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const AnimatedFeedCard(isCompleted: true, child: Text('carte')),
        disableAnimations: true,
      ),
    );

    expect(rule(), findsOneWidget);

    // `_startDelayed` (220 ms, non annulable) est armé par `animate: true` :
    // on le laisse expirer, sinon le binding signale un Timer pendant.
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pump(const Duration(milliseconds: 350));
  });

  testWidgets('une carte jamais aboutie se démonte sans lever', (tester) async {
    // Régression : le contrôleur était `late final` et n'était instancié qu'au
    // `dispose()` d'une carte non aboutie — `vsync: this` allait alors chercher
    // un ancêtre désactivé.
    await tester.pumpWidget(
      wrap(const AnimatedFeedCard(isCompleted: false, child: Text('carte'))),
    );
    await tester.pumpWidget(wrap(const SizedBox()));

    expect(tester.takeException(), isNull);
  });
}
