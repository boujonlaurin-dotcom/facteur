import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/release_notes/models/changelog_entry.dart';
import 'package:facteur/features/release_notes/providers/changelog_provider.dart';
import 'package:facteur/features/release_notes/widgets/changelog_banner.dart';

Widget _harness(Future<List<ChangelogRelease>> Function() futureBuilder) {
  return ProviderScope(
    overrides: [
      unseenReleasesProvider.overrideWith((_) => futureBuilder()),
    ],
    child: MaterialApp(
      theme: FacteurTheme.lightTheme,
      home: const Scaffold(body: ChangelogBanner()),
    ),
  );
}

void main() {
  testWidgets('renders nothing when there are no unseen releases',
      (tester) async {
    await tester.pumpWidget(_harness(() async => const []));
    await tester.pumpAndSettle();

    expect(find.byType(ChangelogBanner), findsOneWidget);
    expect(find.byType(InkWell), findsNothing);
  });

  testWidgets('renders concatenated tags when releases are unseen',
      (tester) async {
    await tester.pumpWidget(_harness(() async => const [
          ChangelogRelease(
            version: '1.2.0',
            date: '2026-06-09',
            entries: [
              ChangelogEntry(tag: 'Perspectives', summary: 'A.'),
            ],
          ),
          ChangelogRelease(
            version: '1.1.0',
            date: '2026-05-01',
            entries: [
              ChangelogEntry(tag: 'Carte', summary: 'B.'),
            ],
          ),
        ]));
    await tester.pumpAndSettle();

    expect(find.text('Perspectives, Carte'), findsOneWidget);
    expect(find.byType(InkWell), findsWidgets);
  });

  testWidgets('renders nothing while loading', (tester) async {
    final completer = Completer<List<ChangelogRelease>>();
    await tester.pumpWidget(_harness(() => completer.future));
    await tester.pump();

    expect(find.byType(InkWell), findsNothing);
  });
}
