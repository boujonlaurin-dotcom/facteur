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

    test(
      'back rétrocompatible : pas de highlight_spans/shared_tokens → listes vides',
      () {
        final data = PerspectiveData.fromJson({
          'title': 'X',
          'url': 'https://y.fr',
          'source_name': 'Y',
          'source_domain': 'y.fr',
          'bias_stance': 'unknown',
        });

        expect(data.highlightSpans, isEmpty);
        expect(data.sharedTokens, isEmpty);
      },
    );

    test('valeurs vides parsent en listes vides (pas de crash)', () {
      final data = PerspectiveData.fromJson({
        'title': 'X',
        'url': 'https://y.fr',
        'source_name': 'Y',
        'source_domain': 'y.fr',
        'bias_stance': 'unknown',
        'highlight_spans': <dynamic>[],
        'shared_tokens': <dynamic>[],
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
        'partial': true,
        'divergence_level': 'medium',
        'reference_pivot': {'start': 7, 'end': 14, 'text': 'frappe'},
      });
      expect(res.partial, isTrue);
      expect(res.divergenceLevel, 'medium');
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

    test('deep_recommendation + deep_pending parsés quand fournis', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
        'deep_pending': false,
        'deep_recommendation': {
          'content_id': 'abc-123',
          'title': 'Le fond du sujet',
          'url': 'https://lemonde.fr/fond',
          'thumbnail_url': 'https://img/x.jpg',
          'content_type': 'article',
          'source_id': 'src-1',
          'source_name': 'Le Monde',
          'source_logo_url': 'https://logo/lm.png',
          'published_at': '2026-06-10T08:00:00+00:00',
          'match_reason': 'Analyse de fond sur le même dossier.',
          'description': 'Un long format.',
        },
      });
      expect(res.deepPending, isFalse);
      expect(res.deepRecommendation, isNotNull);
      final reco = res.deepRecommendation!;
      expect(reco.contentId, 'abc-123');
      expect(reco.title, 'Le fond du sujet');
      expect(reco.url, 'https://lemonde.fr/fond');
      expect(reco.thumbnailUrl, 'https://img/x.jpg');
      expect(reco.contentType, 'article');
      expect(reco.sourceId, 'src-1');
      expect(reco.sourceName, 'Le Monde');
      expect(reco.sourceLogoUrl, 'https://logo/lm.png');
      expect(reco.publishedAt, '2026-06-10T08:00:00+00:00');
      expect(reco.matchReason, 'Analyse de fond sur le même dossier.');
      expect(reco.description, 'Un long format.');
    });

    test('deep_pending true + deep_recommendation null (calcul en cours)', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
        'deep_pending': true,
        'deep_recommendation': null,
      });
      expect(res.deepPending, isTrue);
      expect(res.deepRecommendation, isNull);
    });

    test('clés deep absentes → null / false (rétro-compat back ancien)', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
      });
      expect(res.deepRecommendation, isNull);
      expect(res.deepPending, isFalse);
    });
  });

  group('DeepRecommendation.fromJson', () {
    test('tous les champs présents', () {
      final reco = DeepRecommendation.fromJson(<String, dynamic>{
        'content_id': 'id-9',
        'title': 'Titre',
        'url': 'https://x.fr',
        'thumbnail_url': 'https://x.fr/t.jpg',
        'content_type': 'video',
        'source_id': 's-9',
        'source_name': 'Source',
        'source_logo_url': 'https://x.fr/l.png',
        'published_at': '2026-01-01T00:00:00Z',
        'match_reason': 'raison',
        'description': 'desc',
      });
      expect(reco.contentId, 'id-9');
      expect(reco.contentType, 'video');
      expect(reco.matchReason, 'raison');
    });

    test('champs optionnels null → valeurs par défaut sûres', () {
      final reco = DeepRecommendation.fromJson(<String, dynamic>{
        'content_id': 'id-1',
        'title': 'Titre seul',
      });
      expect(reco.contentId, 'id-1');
      expect(reco.title, 'Titre seul');
      expect(reco.url, isNull);
      expect(reco.thumbnailUrl, isNull);
      expect(reco.contentType, 'article'); // défaut
      expect(reco.sourceId, isNull);
      expect(reco.sourceName, '');
      expect(reco.sourceLogoUrl, isNull);
      expect(reco.publishedAt, isNull);
      expect(reco.matchReason, '');
      expect(reco.description, isNull);
    });
  });

  group('TokenSpan.fromJsonOrNull', () {
    test('retourne null pour input non-Map', () {
      expect(TokenSpan.fromJsonOrNull(null), isNull);
      expect(TokenSpan.fromJsonOrNull('foo'), isNull);
      expect(TokenSpan.fromJsonOrNull(42), isNull);
    });

    test('parse une Map valide', () {
      final span = TokenSpan.fromJsonOrNull({
        'start': 1,
        'end': 5,
        'text': 'foo',
      });
      expect(span, isNotNull);
      expect(span!.start, 1);
      expect(span.end, 5);
      expect(span.text, 'foo');
    });
  });
}
