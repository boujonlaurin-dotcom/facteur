import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/swipe_to_open_card.dart';

Widget _wrap({
  required VoidCallback onOpen,
  VoidCallback? onDismiss,
}) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(
      body: Center(
        child: SwipeToOpenCard(
          onSwipeOpen: onOpen,
          onSwipeDismiss: onDismiss,
          child: const ColoredBox(
            key: ValueKey('card'),
            color: Colors.white,
            child: SizedBox(width: 300, height: 120),
          ),
        ),
      ),
    ),
  );
}

Transform _cardTransform(WidgetTester tester) {
  return tester.widget<Transform>(
    find.ancestor(
      of: find.byKey(const ValueKey('card')),
      matching: find.byType(Transform),
    ),
  );
}

void main() {
  testWidgets('right swipe opens and resets translation before returning',
      (tester) async {
    var opened = 0;
    await tester.pumpWidget(_wrap(onOpen: () => opened++));

    await tester.drag(find.byKey(const ValueKey('card')), const Offset(260, 0));
    await tester.pump();

    expect(opened, 1);
    expect(_cardTransform(tester).transform.getTranslation().x, 0);
  });

  testWidgets('left swipe triggers dismiss feedback callback', (tester) async {
    var dismissed = 0;
    await tester.pumpWidget(
      _wrap(onOpen: () {}, onDismiss: () => dismissed++),
    );

    await tester.drag(
      find.byKey(const ValueKey('card')),
      const Offset(-260, 0),
    );
    await tester.pump();

    expect(dismissed, 1);
  });
}
