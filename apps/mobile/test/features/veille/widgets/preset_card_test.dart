import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import 'package:facteur/features/veille/widgets/veille_widgets.dart';

void main() {
  testWidgets('PresetCard renders label + accroche and triggers onTap',
      (tester) async {
    var tapped = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PresetCard(
            label: 'Outils IA agentique',
            accroche: 'Les derniers outils et bonnes pratiques',
            icon: PhosphorIcons.lightning(),
            onTap: () => tapped++,
          ),
        ),
      ),
    );

    expect(find.text('Outils IA agentique'), findsOneWidget);
    expect(find.text('Les derniers outils et bonnes pratiques'), findsOneWidget);

    await tester.tap(find.byType(InkWell));
    expect(tapped, 1);
  });
}
