import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/sources/models/source_model.dart';
import 'package:facteur/features/sources/providers/sources_providers.dart';
import 'package:facteur/features/sources/widgets/catalog_sources_strip.dart';

Source _curated(String id, String name, String theme) => Source(
      id: id,
      name: name,
      type: SourceType.article,
      theme: theme,
      isCurated: true,
    );

/// Fake notifier : sert un catalogue figé sans toucher au réseau.
class _FakeUserSources extends UserSourcesNotifier {
  _FakeUserSources(this._sources);
  final List<Source> _sources;

  @override
  Future<List<Source>> build() async => _sources;
}

Widget _wrap(Widget child, List<Source> sources) {
  return ProviderScope(
    overrides: [
      userSourcesProvider.overrideWith(() => _FakeUserSources(sources)),
    ],
    child: MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: child)),
    ),
  );
}

void main() {
  testWidgets(
      'initialTheme + initiallyExpanded : catalogue déplié et filtré sur le '
      'thème dès le rendu', (tester) async {
    await tester.pumpWidget(_wrap(
      CatalogSourcesStrip(
        onSourceTap: (_) {},
        initialTheme: 'tech',
        initiallyExpanded: true,
      ),
      [
        _curated('s1', 'Numerama', 'tech'),
        _curated('s2', 'Le Monde', 'politics'),
      ],
    ));
    await tester.pumpAndSettle();

    // Déplié d'emblée + filtré sur tech : seule la source tech est listée.
    expect(find.text('Numerama'), findsOneWidget);
    expect(find.text('Le Monde'), findsNothing);
  });
}
