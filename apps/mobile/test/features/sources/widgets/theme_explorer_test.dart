import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:facteur/features/sources/widgets/theme_explorer.dart';
import 'package:facteur/features/sources/models/theme_source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/config/theme.dart';

void main() {
  group('ThemeExplorer', () {
    final mockThemes = [
      const FollowedTheme(slug: 'tech', name: 'Tech'),
      const FollowedTheme(slug: 'finance', name: 'Finance'),
      const FollowedTheme(slug: 'sport', name: 'Sport'),
    ];

    testWidgets('renders followed themes as chips', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themesFollowedProvider.overrideWith((_) async => mockThemes),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: const Scaffold(body: ThemeExplorer()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tech'), findsOneWidget);
      expect(find.text('Finance'), findsOneWidget);
      expect(find.text('Sport'), findsOneWidget);
    });

    testWidgets('shows default themes when user has none', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themesFollowedProvider
                .overrideWith((_) async => <FollowedTheme>[]),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: const Scaffold(body: ThemeExplorer()),
          ),
        ),
      );

      await tester.pumpAndSettle();

      expect(find.text('Tech'), findsOneWidget);
      expect(find.text('Actu FR'), findsOneWidget);
      expect(find.text('Produit'), findsOneWidget);
    });

    testWidgets('displays section title', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themesFollowedProvider.overrideWith((_) async => mockThemes),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: const Scaffold(body: ThemeExplorer()),
          ),
        ),
      );

      expect(find.text('Explorer par theme'), findsOneWidget);
    });

    testWidgets('shows placeholder chips while loading', (tester) async {
      // Use a Completer to simulate loading without a pending timer
      final completer = Completer<List<FollowedTheme>>();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            themesFollowedProvider.overrideWith((_) => completer.future),
          ],
          child: MaterialApp(
            theme: FacteurTheme.lightTheme,
            home: const Scaffold(body: ThemeExplorer()),
          ),
        ),
      );

      // While loading, should not show theme names yet
      expect(find.text('Tech'), findsNothing);
      expect(find.text('Finance'), findsNothing);

      // Complete the future to avoid pending timer
      completer.complete(mockThemes);
      await tester.pumpAndSettle();
    });
  });
}
