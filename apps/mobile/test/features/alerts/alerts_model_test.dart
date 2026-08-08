import 'package:facteur/features/alerts/models/alert_item.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('AlertsState.fromJson', () {
    test('parse la réponse complète du backend', () {
      final state = AlertsState.fromJson({
        'cap': 5,
        'active_count': 2,
        'items': [
          {
            'source_id': 'src-1',
            'source_name': 'Le Mensuel',
            'source_logo_url': 'https://example.com/logo.png',
            'articles_30d': 2,
            'last_published_at': '2026-07-20T08:00:00Z',
            'last_alert_sent_at': '2026-07-20T09:00:00Z',
            'new_content': 1,
          },
          {
            'source_id': 'src-2',
            'source_name': 'La Revue',
            'new_content': 0,
          },
        ],
      });

      expect(state.cap, 5);
      expect(state.activeCount, 2);
      expect(state.items, hasLength(2));
      expect(state.items.first.sourceName, 'Le Mensuel');
      expect(state.items.first.lastPublishedAt, isNotNull);
      expect(state.items.last.sourceLogoUrl, isNull);
      expect(state.items.last.articles30d, 0);
    });

    test('tolère les champs absents', () {
      final state = AlertsState.fromJson({});
      expect(state.cap, 5);
      expect(state.activeCount, 0);
      expect(state.items, isEmpty);
    });

    test('withNewContent ne garde que les cloches qui ont du neuf', () {
      final state = AlertsState.fromJson({
        'cap': 5,
        'active_count': 2,
        'items': [
          {'source_id': 'a', 'source_name': 'A', 'new_content': 3},
          {'source_id': 'b', 'source_name': 'B', 'new_content': 0},
        ],
      });

      expect(state.withNewContent, hasLength(1));
      expect(state.withNewContent.single.sourceId, 'a');
    });

    test('isFull au plafond', () {
      expect(
        AlertsState.fromJson({'cap': 5, 'active_count': 5}).isFull,
        isTrue,
      );
      expect(
        AlertsState.fromJson({'cap': 5, 'active_count': 4}).isFull,
        isFalse,
      );
    });
  });

  // Story 30.4 — la cloche porte désormais ses contenus déclencheurs.
  group('AlertItem.contents', () {
    test('parse les contenus et leur source réelle', () {
      final state = AlertsState.fromJson({
        'items': [
          {
            'kind': 'topic',
            'source_id': 'topic-1',
            'source_name': 'Ligue 1',
            'new_content': 2,
            'contents': [
              {
                'content_id': 'c-1',
                'title': 'Ligue 1 : le résumé',
                'url': 'https://example.com/1',
                'thumbnail_url': 'https://img.example/1.jpg',
                'published_at': '2026-08-08T06:00:00Z',
                'content_type': 'article',
                'source_id': 'src-9',
                'source_name': 'L’Équipe',
                'source_logo_url': 'https://logo.example/9.png',
              },
            ],
          },
        ],
      });

      final content = state.items.single.contents.single;
      expect(content.contentId, 'c-1');
      expect(content.title, 'Ligue 1 : le résumé');
      // La source du *contenu*, pas la cible de la cloche : c'est ce qui rend
      // une alerte sujet lisible.
      expect(content.sourceName, 'L’Équipe');
      expect(content.sourceId, 'src-9');
      expect(content.publishedAt, isNotNull);
    });

    test('un payload v1 (sans `contents`) reste parsable', () {
      final state = AlertsState.fromJson({
        'items': [
          {'source_id': 'a', 'source_name': 'A', 'new_content': 2},
        ],
      });

      expect(state.items.single.contents, isEmpty);
      expect(state.items.single.newContent, 2);
      expect(state.withNewContent, hasLength(1));
    });

    test('un contenu sans id est écarté (jamais de tap dans le vide)', () {
      final state = AlertsState.fromJson({
        'items': [
          {
            'source_id': 'a',
            'source_name': 'A',
            'new_content': 1,
            'contents': [
              {'title': 'Sans id'},
              {'content_id': 'ok', 'title': 'Avec id'},
            ],
          },
        ],
      });

      expect(
        state.items.single.contents.map((c) => c.contentId),
        ['ok'],
      );
    });

    test('toPreviewContent alimente le header peint au 1ᵉʳ frame', () {
      const content = AlertContent(
        contentId: 'c-1',
        title: 'Un titre',
        url: 'https://example.com/1',
        thumbnailUrl: 'https://img.example/1.jpg',
        contentType: 'video',
        sourceId: 'src-1',
        sourceName: 'Le Mensuel',
        sourceLogoUrl: 'https://logo.example/1.png',
      );

      final preview = content.toPreviewContent();
      expect(preview.id, 'c-1');
      expect(preview.title, 'Un titre');
      expect(preview.url, 'https://example.com/1');
      expect(preview.thumbnailUrl, 'https://img.example/1.jpg');
      expect(preview.contentType, ContentType.video);
      expect(preview.source.name, 'Le Mensuel');
      expect(preview.source.logoUrl, 'https://logo.example/1.png');
    });
  });

  group('buildAlertRows', () {
    AlertContent content(String id) => AlertContent(contentId: id, title: id);
    AlertItem alert(String id, List<String> contentIds) => AlertItem(
          sourceId: id,
          sourceName: id,
          newContent: contentIds.length,
          contents: contentIds.map(content).toList(),
        );

    test('une seule cloche : mini-flux, on descend dans ses articles', () {
      final rows = buildAlertRows([
        alert('A', ['a1', 'a2', 'a3', 'a4']),
      ], maxRows: 3);

      expect(rows.map((r) => r.content!.contentId), ['a1', 'a2', 'a3']);
    });

    test('plusieurs cloches : tourniquet, une chacune d’abord', () {
      final rows = buildAlertRows([
        alert('A', ['a1', 'a2']),
        alert('B', ['b1', 'b2']),
        alert('C', ['c1']),
      ], maxRows: 3);

      expect(rows.map((r) => r.content!.contentId), ['a1', 'b1', 'c1']);
    });

    test('deux cloches : on complète avec le 2ᵉ article de chacune', () {
      final rows = buildAlertRows([
        alert('A', ['a1', 'a2']),
        alert('B', ['b1']),
      ], maxRows: 3);

      expect(rows.map((r) => r.content!.contentId), ['a1', 'b1', 'a2']);
    });

    test('une cloche sans contenu ne prend pas de ligne fantôme', () {
      final rows = buildAlertRows([
        alert('A', ['a1']),
        const AlertItem(sourceId: 'B', sourceName: 'B', newContent: 4),
      ], maxRows: 3);

      expect(rows, hasLength(1));
      expect(rows.single.alert.sourceName, 'A');
    });

    test('aucun contenu du tout : on garde les lignes « N nouveaux » (v1)', () {
      final rows = buildAlertRows([
        const AlertItem(sourceId: 'A', sourceName: 'A', newContent: 2),
        const AlertItem(sourceId: 'B', sourceName: 'B', newContent: 1),
      ], maxRows: 3);

      expect(rows, hasLength(2));
      expect(rows.every((r) => r.content == null), isTrue);
    });

    test('liste vide ou budget nul : aucune ligne', () {
      expect(buildAlertRows(const [], maxRows: 3), isEmpty);
      expect(buildAlertRows([alert('A', ['a1'])], maxRows: 0), isEmpty);
    });
  });
}
