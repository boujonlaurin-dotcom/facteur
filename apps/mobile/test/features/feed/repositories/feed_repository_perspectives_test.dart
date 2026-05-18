import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/repositories/feed_repository.dart';

void main() {
  group('PerspectiveData.fromJson', () {
    test('parse highlight_spans + shared_tokens quand fournis', () {
      final data = PerspectiveData.fromJson({
        'title': 'Macron annonce une réforme',
        'url': 'https://lemonde.fr/x',
        'source_name': 'Le Monde',
        'source_domain': 'lemonde.fr',
        'bias_stance': 'center-left',
        'published_at': null,
        'highlight_spans': [
          {'start': 7, 'end': 14, 'text': 'annonce', 'bias': 'left'},
        ],
        'shared_tokens': [
          {'start': 0, 'end': 6, 'text': 'Macron'},
          {'start': 19, 'end': 26, 'text': 'réforme'},
        ],
      });

      expect(data.title, 'Macron annonce une réforme');
      expect(data.highlightSpans, hasLength(1));
      expect(data.highlightSpans.first.text, 'annonce');
      expect(data.highlightSpans.first.bias, 'left');
      expect(data.sharedTokens, hasLength(2));
      expect(data.sharedTokens.first.start, 0);
      expect(data.sharedTokens.first.text, 'Macron');
    });

    test('back rétrocompatible : pas de highlight_spans/shared_tokens → listes vides', () {
      final data = PerspectiveData.fromJson({
        'title': 'X',
        'url': 'https://y.fr',
        'source_name': 'Y',
        'source_domain': 'y.fr',
        'bias_stance': 'unknown',
      });

      expect(data.highlightSpans, isEmpty);
      expect(data.sharedTokens, isEmpty);
    });

    test('valeurs vides parsent en listes vides (pas de crash)', () {
      final data = PerspectiveData.fromJson({
        'title': 'X',
        'url': 'https://y.fr',
        'source_name': 'Y',
        'source_domain': 'y.fr',
        'bias_stance': 'unknown',
        'highlight_spans': [],
        'shared_tokens': [],
      });
      expect(data.highlightSpans, isEmpty);
      expect(data.sharedTokens, isEmpty);
    });
  });

  group('PerspectivesResponse.fromJson', () {
    test('parse reference_pivot quand fourni', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
        'reference_pivot': {'start': 7, 'end': 14, 'text': 'frappe'},
      });
      expect(res.referencePivot, isNotNull);
      expect(res.referencePivot!.start, 7);
      expect(res.referencePivot!.end, 14);
      expect(res.referencePivot!.text, 'frappe');
    });

    test('reference_pivot null → champ null (pas de wash côté front)', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
        'reference_pivot': null,
      });
      expect(res.referencePivot, isNull);
    });

    test('reference_pivot absent → null (back pas encore déployé)', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
      });
      expect(res.referencePivot, isNull);
    });
  });

  group('TokenSpan.fromJsonOrNull', () {
    test('retourne null pour input non-Map', () {
      expect(TokenSpan.fromJsonOrNull(null), isNull);
      expect(TokenSpan.fromJsonOrNull('foo'), isNull);
      expect(TokenSpan.fromJsonOrNull(42), isNull);
    });

    test('parse une Map valide', () {
      final span = TokenSpan.fromJsonOrNull(
        {'start': 1, 'end': 5, 'text': 'foo'},
      );
      expect(span, isNotNull);
      expect(span!.start, 1);
      expect(span.end, 5);
      expect(span.text, 'foo');
    });
  });
}
