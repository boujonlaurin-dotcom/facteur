import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

Perspective _persp(String name, String bias) => Perspective(
      title: 'Titre pour $name',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: bias,
    );

Future<void> _pumpSection(
  WidgetTester tester, {
  required Set<String>? selectedSegments,
}) async {
  final perspectives = [
    _persp('Source-Gauche', 'left'),
    _persp('Source-CentreG', 'center-left'),
    _persp('Source-Centre', 'center'),
    _persp('Source-CentreD', 'center-right'),
    _persp('Source-Droite', 'right'),
  ];

  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SingleChildScrollView(
            child: SizedBox(
              width: 390,
              child: PerspectivesInlineSection(
                perspectives: perspectives,
                biasDistribution: const {
                  'left': 1,
                  'center-left': 1,
                  'center': 1,
                  'center-right': 1,
                  'right': 1,
                },
                keywords: const [],
                contentId: 'test-content-id',
                externalSelectedSegments: selectedSegments,
                onSegmentTap: (_) {},
                onClearSegments: () {},
                onToggle: () {},
                isExpanded: true,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('shows all variants when selectedSegments is null', (tester) async {
    await _pumpSection(tester, selectedSegments: null);

    expect(find.text('Source-Gauche'), findsOneWidget);
    expect(find.text('Source-CentreG'), findsOneWidget);
    expect(find.text('Source-Centre'), findsOneWidget);
    expect(find.text('Source-CentreD'), findsOneWidget);
    expect(find.text('Source-Droite'), findsOneWidget);
  });

  testWidgets('shows all variants when selectedSegments is empty', (tester) async {
    await _pumpSection(tester, selectedSegments: const <String>{});

    expect(find.text('Source-Gauche'), findsOneWidget);
    expect(find.text('Source-Centre'), findsOneWidget);
    expect(find.text('Source-Droite'), findsOneWidget);
  });

  testWidgets("shows only left-leaning variants when selected = {'gauche'}",
      (tester) async {
    await _pumpSection(tester, selectedSegments: const {'gauche'});

    expect(find.text('Source-Gauche'), findsOneWidget);
    expect(find.text('Source-CentreG'), findsOneWidget);
    expect(find.text('Source-Centre'), findsNothing);
    expect(find.text('Source-CentreD'), findsNothing);
    expect(find.text('Source-Droite'), findsNothing);
  });

  testWidgets("shows centre-only when selected = {'centre'}", (tester) async {
    await _pumpSection(tester, selectedSegments: const {'centre'});

    expect(find.text('Source-Gauche'), findsNothing);
    expect(find.text('Source-CentreG'), findsNothing);
    expect(find.text('Source-Centre'), findsOneWidget);
    expect(find.text('Source-CentreD'), findsNothing);
    expect(find.text('Source-Droite'), findsNothing);
  });

  testWidgets("shows gauche+droite when selected = {'gauche','droite'}",
      (tester) async {
    await _pumpSection(tester, selectedSegments: const {'gauche', 'droite'});

    expect(find.text('Source-Gauche'), findsOneWidget);
    expect(find.text('Source-CentreG'), findsOneWidget);
    expect(find.text('Source-Centre'), findsNothing);
    expect(find.text('Source-CentreD'), findsOneWidget);
    expect(find.text('Source-Droite'), findsOneWidget);
  });
}
