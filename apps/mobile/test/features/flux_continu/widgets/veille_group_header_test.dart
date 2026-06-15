import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/widgets/veille_group_header.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Content _content(String id, {String? group}) => Content(
      id: id,
      title: 'Titre $id',
      url: 'https://x.test/$id',
      contentType: ContentType.article,
      publishedAt: DateTime(2026, 1, 1),
      source: Source(id: 's', name: 'S', type: SourceType.article),
      veilleGroup: group,
    );

void main() {
  group('buildVeilleFeedRows', () {
    test('insère un en-tête à chaque transition de groupe', () {
      final items = [
        _content('a', group: 'sources'),
        _content('b', group: 'sources'),
        _content('c', group: 'elargie'),
      ];
      final rows = buildVeilleFeedRows(items);

      // 2 en-têtes (un par bloc) + 3 cartes.
      final headers = rows.whereType<VeilleHeaderRow>().toList();
      expect(headers.map((h) => h.label).toList(),
          [kVeilleSourcesLabel, kVeilleElargieLabel]);
      expect(rows.whereType<VeilleArticleRow>().length, 3);

      // Ordre : en-tête « Tes sources » avant la 1ʳᵉ carte.
      expect(rows.first, isA<VeilleHeaderRow>());
      expect((rows.first as VeilleHeaderRow).label, kVeilleSourcesLabel);
    });

    test('un seul en-tête quand un seul bloc est présent', () {
      final items = [
        _content('a', group: 'sources'),
        _content('b', group: 'sources'),
      ];
      final rows = buildVeilleFeedRows(items);
      expect(rows.whereType<VeilleHeaderRow>().length, 1);
    });

    test('aucun en-tête quand veilleGroup est absent (backward-safe)', () {
      final items = [_content('a'), _content('b')];
      final rows = buildVeilleFeedRows(items);
      expect(rows.whereType<VeilleHeaderRow>(), isEmpty);
      expect(rows.whereType<VeilleArticleRow>().length, 2);
    });

    test('préserve l\'index d\'origine des cartes', () {
      final items = [
        _content('a', group: 'sources'),
        _content('b', group: 'elargie'),
      ];
      final rows = buildVeilleFeedRows(items);
      final articles = rows.whereType<VeilleArticleRow>().toList();
      expect(articles[0].index, 0);
      expect(articles[1].index, 1);
    });
  });

  testWidgets('VeilleGroupHeader rend son libellé', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: VeilleGroupHeader(label: kVeilleElargieLabel)),
      ),
    );
    expect(find.text(kVeilleElargieLabel), findsOneWidget);
  });
}
