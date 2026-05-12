import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/digest/widgets/a_la_une_badge.dart';

void main() {
  group('ALaUneBadge', () {
    testWidgets('rend libellé + count quand sourceCount >= 2', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ALaUneBadge(sourceCount: 4)),
        ),
      );

      expect(find.text('À LA UNE · 4 sources'), findsOneWidget);
    });
  });
}
