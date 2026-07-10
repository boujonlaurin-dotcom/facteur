import 'package:facteur/features/flux_continu/repositories/flux_continu_repository.dart';
import 'package:flutter_test/flutter_test.dart';

/// Story 22.3 — `TopTheme.fromJson` parse les champs additifs (origin / kind /
/// source_id / daily_rank / reason) tout en restant rétro-compatible avec les
/// payloads pré-22.3 (défauts `theme` / `validated`).
void main() {
  group('TopTheme.fromJson (Story 22.3)', () {
    test('legacy payload defaults to validated theme', () {
      final t = TopTheme.fromJson({
        'interest_slug': 'tech',
        'weight': 1.5,
        'article_count': 3,
      });
      expect(t.interestSlug, 'tech');
      expect(t.kind, 'theme');
      expect(t.origin, 'validated');
      expect(t.isSuggested, isFalse);
      expect(t.sourceId, isNull);
      expect(t.reason, isNull);
      expect(t.dailyRank, 0);
    });

    test('parses a suggested theme with reason + daily_rank', () {
      final t = TopTheme.fromJson({
        'interest_slug': 'science',
        'weight': 1.0,
        'article_count': 7,
        'kind': 'theme',
        'origin': 'suggested',
        'daily_rank': 2,
        'reason': {
          'label': 'Tu suis ce thème',
          'breakdown': [
            {'label': 'Tu suis ce thème', 'points': 100, 'pillar': 'pertinence'},
            {'label': '7 articles récents', 'points': 60, 'pillar': 'fraicheur'},
          ],
        },
      });
      expect(t.isSuggested, isTrue);
      expect(t.dailyRank, 2);
      expect(t.reason, isNotNull);
      expect(t.reason!.label, 'Tu suis ce thème');
      expect(t.reason!.breakdown, hasLength(2));
    });

    test('parses a suggested source with source_id', () {
      final t = TopTheme.fromJson({
        'interest_slug': 'politics',
        'weight': 1.0,
        'article_count': 5,
        'kind': 'source',
        'source_id': 'abc-123',
        'origin': 'suggested',
        'daily_rank': 1,
        'reason': {'label': 'Tu suis cette source', 'breakdown': <dynamic>[]},
      });
      expect(t.kind, 'source');
      expect(t.sourceId, 'abc-123');
      expect(t.isSuggested, isTrue);
    });
  });
}
