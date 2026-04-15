import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/features/sources/screens/theme_sources_screen.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/models/theme_source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/config/theme.dart';

void main() {
  group('ThemeSourcesScreen', () {
    final mockResponse = ThemeSourcesResponse(
      curated: [
        Source(id: 'c1', name: 'The Verge', type: SourceType.article),
        Source(id: 'c2', name: 'Ars Technica', type: SourceType.article),
      ],
      candidates: [
        Source(id: 'ca1', name: 'Hacker News', type: SourceType.article),
      ],
      community: [
        Source(id: 'co1', name: "Lenny's Newsletter", type: SourceType.article),
      ],
    );

    Widget buildTestWidget(ThemeSourcesResponse response) {
      return ProviderScope(
        overrides: [
          sourcesByThemeProvider('tech').overrideWith((_) async => response),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: const ThemeSourcesScreen(
            themeSlug: 'tech',
            themeName: 'Tech',
          ),
        ),
      );
    }

    testWidgets('renders all 3 section headers', (tester) async {
      await tester.pumpWidget(buildTestWidget(mockResponse));
      await tester.pumpAndSettle();

      expect(find.text('Sources curees'), findsOneWidget);
      expect(find.text('Candidates'), findsOneWidget);
      expect(find.text('Decouvertes par la communaute'), findsOneWidget);
    });

    testWidgets('renders source names', (tester) async {
      await tester.pumpWidget(buildTestWidget(mockResponse));
      await tester.pumpAndSettle();

      expect(find.text('The Verge'), findsOneWidget);
      expect(find.text('Ars Technica'), findsOneWidget);
      expect(find.text('Hacker News'), findsOneWidget);
      expect(find.text("Lenny's Newsletter"), findsOneWidget);
    });

    testWidgets('shows section counts', (tester) async {
      await tester.pumpWidget(buildTestWidget(mockResponse));
      await tester.pumpAndSettle();

      expect(find.text('2'), findsOneWidget); // curated count
      expect(find.text('1'), findsNWidgets(2)); // candidates + community
    });

    testWidgets('shows empty state when no sources', (tester) async {
      const emptyResponse = ThemeSourcesResponse(
        curated: [],
        candidates: [],
        community: [],
      );

      await tester.pumpWidget(buildTestWidget(emptyResponse));
      await tester.pumpAndSettle();

      expect(find.text('Aucune source pour ce theme.'), findsOneWidget);
    });

    testWidgets('hides empty sections', (tester) async {
      final partialResponse = ThemeSourcesResponse(
        curated: [
          Source(id: 'c1', name: 'The Verge', type: SourceType.article),
        ],
        candidates: [],
        community: [],
      );

      await tester.pumpWidget(buildTestWidget(partialResponse));
      await tester.pumpAndSettle();

      expect(find.text('Sources curees'), findsOneWidget);
      expect(find.text('Candidates'), findsNothing);
      expect(find.text('Decouvertes par la communaute'), findsNothing);
    });

    testWidgets('displays theme name in app bar', (tester) async {
      await tester.pumpWidget(buildTestWidget(mockResponse));
      await tester.pumpAndSettle();

      expect(find.text('Tech'), findsOneWidget);
    });

    testWidgets('shows loading indicator while fetching', (tester) async {
      final completer = Completer<ThemeSourcesResponse>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            sourcesByThemeProvider('tech')
                .overrideWith((_) => completer.future),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: const ThemeSourcesScreen(
              themeSlug: 'tech',
              themeName: 'Tech',
            ),
          ),
        ),
      );

      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      completer.complete(mockResponse);
      await tester.pumpAndSettle();
    });
  });
}
