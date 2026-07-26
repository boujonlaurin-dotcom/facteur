import 'package:facteur/features/alerts/models/alert_item.dart';
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
}
