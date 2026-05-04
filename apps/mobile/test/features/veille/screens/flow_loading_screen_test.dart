import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/screens/transitions/flow_loading_screen.dart';

Widget _wrap({required int from}) {
  return ProviderScope(
    child: MaterialApp(
      home: Scaffold(
        body: FlowLoadingScreen(from: from),
      ),
    ),
  );
}

void main() {
  testWidgets('from=4 affiche eyebrow et titre dédiés à la première livraison',
      (tester) async {
    await tester.pumpWidget(_wrap(from: 4));
    await tester.pump();

    // L'eyebrow est rendu en majuscules par VeilleAiEyebrow.
    expect(
      find.text('LE FACTEUR PRÉPARE TA PREMIÈRE LIVRAISON…'),
      findsOneWidget,
    );
    expect(find.text('Première veille en cours'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('from=1 affiche les labels du Step 1 (analyse thème)',
      (tester) async {
    await tester.pumpWidget(_wrap(from: 1));
    await tester.pump();

    expect(find.text('Analyse de ton thème'), findsOneWidget);

    await _disposeTree(tester);
  });

  testWidgets('from inconnu → fallback sur le label Step 1', (tester) async {
    await tester.pumpWidget(_wrap(from: 99));
    await tester.pump();

    expect(find.text('Analyse de ton thème'), findsOneWidget);

    await _disposeTree(tester);
  });
}

/// Force le démontage du widget tree pour disposer les AnimationControllers
/// du loader et éviter les "Timer still pending" à la sortie du test.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
}
