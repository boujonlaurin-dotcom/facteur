import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

/// État `throttled` du bottom sheet « Analyse Facteur » (#1109) : le cap
/// quotidien n'est PAS une erreur — message seul, sans bouton « Réessayer ».
void main() {
  Future<void> openSheet(
    WidgetTester tester,
    ValueNotifier<AnalysisSheetData> data,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showAnalysisBottomSheet(
                  context: context,
                  data: data,
                  perspectives: const [],
                  coverageCount: 5,
                  onRetry: () {},
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('throttled : message avec coverageCount, pas de Réessayer',
      (tester) async {
    final data = ValueNotifier(
      const AnalysisSheetData(state: PerspectivesAnalysisState.throttled),
    );
    addTearDown(data.dispose);

    await openSheet(tester, data);

    expect(find.text(analysisThrottledText(5)), findsOneWidget);
    expect(find.text('Réessayer'), findsNothing);
    expect(find.text('Analyse indisponible'), findsNothing);
  });

  testWidgets('error garde le bouton Réessayer (non-régression)',
      (tester) async {
    final data = ValueNotifier(
      const AnalysisSheetData(state: PerspectivesAnalysisState.error),
    );
    addTearDown(data.dispose);

    await openSheet(tester, data);

    expect(find.text('Analyse indisponible'), findsOneWidget);
    expect(find.text('Réessayer'), findsOneWidget);
  });

  test('copy throttled : {N} = coverageCount, pas d\'em-dash', () {
    final copy = analysisThrottledText(7);
    expect(copy, contains('7 articles'));
    expect(copy.contains('—'), isFalse);
  });
}
