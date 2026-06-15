import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

Perspective _persp(String name, {String? language}) => Perspective(
      title: 'Titre pour $name',
      url: 'https://example.com/$name',
      sourceName: name,
      sourceDomain: '',
      biasStance: 'center',
      language: language,
    );

Future<void> _pumpSheet(
  WidgetTester tester, {
  required List<Perspective> perspectives,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(
          body: SizedBox(
            width: 390,
            height: 844,
            child: PerspectivesBottomSheet(
              perspectives: perspectives,
              biasDistribution: const {'center': 0},
              keywords: const [],
              contentId: 'test-content-id',
              sourceBiasStance: 'center',
              sourceName: 'Test',
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

const _foreignDividerLabel = "Couverture à l'étranger";

void main() {
  testWidgets('mix FR + EN → divider + foreign cards under the divider',
      (tester) async {
    await _pumpSheet(tester, perspectives: [
      _persp('Source-FR-1', language: 'fr'),
      _persp('Source-EN-1', language: 'en'),
      _persp('Source-FR-2'),
    ]);

    expect(find.text(_foreignDividerLabel), findsOneWidget);
    expect(find.text('Source-FR-1'), findsOneWidget);
    expect(find.text('Source-FR-2'), findsOneWidget);
    expect(find.text('Source-EN-1'), findsOneWidget);
  });

  testWidgets('0 EN → no divider', (tester) async {
    await _pumpSheet(tester, perspectives: [
      _persp('Source-FR-1', language: 'fr'),
      _persp('Source-FR-2', language: 'fr'),
    ]);

    expect(find.text(_foreignDividerLabel), findsNothing);
  });

  testWidgets('all language=null → no divider (null ≡ fr)', (tester) async {
    await _pumpSheet(tester, perspectives: [
      _persp('Source-A'),
      _persp('Source-B'),
    ]);

    expect(find.text(_foreignDividerLabel), findsNothing);
  });

  testWidgets('100% EN → divider + foreign block', (tester) async {
    await _pumpSheet(tester, perspectives: [
      _persp('Source-EN-1', language: 'en'),
      _persp('Source-EN-2', language: 'de'),
    ]);

    expect(find.text(_foreignDividerLabel), findsOneWidget);
    expect(find.text('Source-EN-1'), findsOneWidget);
    expect(find.text('Source-EN-2'), findsOneWidget);
  });
}
