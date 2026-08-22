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
    test('coverage_count explicite gagne sur la longueur des alternatives', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'coverage_count': 14,
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
      });
      expect(res.coverageCount, 14);
    });

    test('ancien payload : alternatives + média courant', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[
          {
            'title': 'A',
            'url': 'https://a.example',
            'source_name': 'A',
            'source_domain': 'a.example',
            'bias_stance': 'unknown',
          },
          {
            'title': 'B',
            'url': 'https://b.example',
            'source_name': 'B',
            'source_domain': 'b.example',
            'bias_stance': 'center',
          },
        ],
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{'center': 1},
      });
      expect(res.coverageCount, 3);
    });

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

  group('ConsensusBlock.fromJsonOrAbsent', () {
    test('non-Map (absent, null, autre) → absent() : unavailable, vide', () {
      for (final raw in [null, 'x', 42, <dynamic>[]]) {
        final block = ConsensusBlock.fromJsonOrAbsent(raw);
        expect(block.state, ConsensusBlock.stateUnavailable);
        expect(block.qualifier, isNull);
        expect(block.agreements, isEmpty);
        expect(block.disagreements, isEmpty);
        expect(block.cta.agreement, isNull);
        expect(block.cta.disagreement, isNull);
        expect(block.generatedAt, isNull);
        expect(block.isAvailable, isFalse);
        expect(block.isPending, isFalse);
      }
    });

    test('payload nominal available : constats + cta + generated_at', () {
      final block = ConsensusBlock.fromJsonOrAbsent({
        'state': 'available',
        'qualifier': 'polarized',
        'agreements': [
          {
            'text': 'Le fait A est confirmé.',
            'support_count': 4,
            'display_domains': ['lemonde.fr', 'lefigaro.fr'],
            'plus_count': 2,
          },
        ],
        'disagreements': [
          {
            'text': 'Sur la portée, les avis divergent.',
            'support_count': 2,
            'display_domains': ['liberation.fr'],
            'plus_count': 0,
          },
        ],
        'cta': {
          'agreement': {
            'text': 'Le fait A est confirmé.',
            'support_count': 4,
            'display_domains': ['lemonde.fr'],
            'plus_count': 2,
          },
          'disagreement': null,
        },
        'generated_at': '2026-08-22T06:00:00+00:00',
      });

      expect(block.isAvailable, isTrue);
      expect(block.qualifier, 'polarized');
      expect(block.agreements.single.text, 'Le fait A est confirmé.');
      expect(block.agreements.single.supportCount, 4);
      expect(block.agreements.single.plusCount, 2);
      expect(
        block.agreements.single.displayDomains,
        ['lemonde.fr', 'lefigaro.fr'],
      );
      expect(block.disagreements.single.plusCount, 0);
      expect(block.cta.agreement!.text, 'Le fait A est confirmé.');
      expect(block.cta.disagreement, isNull);
      expect(block.generatedAt, '2026-08-22T06:00:00+00:00');
    });

    test('clamps : ≤3 accords, ≤2 désaccords, ≤2 display_domains', () {
      Map<String, dynamic> statement(int i) => {
            'text': 'Constat $i',
            'support_count': 5,
            'display_domains': ['a.fr', 'b.fr', 'c.fr', 'd.fr'],
            'plus_count': 3,
          };
      final block = ConsensusBlock.fromJsonOrAbsent({
        'state': 'available',
        'qualifier': 'varied',
        'agreements': [for (var i = 0; i < 5; i++) statement(i)],
        'disagreements': [for (var i = 0; i < 4; i++) statement(i)],
        'cta': {'agreement': null, 'disagreement': null},
      });

      expect(block.agreements, hasLength(3));
      expect(block.disagreements, hasLength(2));
      expect(block.agreements.first.displayDomains, hasLength(2));
    });

    test('qualifier transmis tel quel, jamais re-dérivé côté client', () {
      // Un qualifier incohérent avec les listes doit passer inchangé : c'est
      // le backend qui calcule, le front applique.
      final block = ConsensusBlock.fromJsonOrAbsent({
        'state': 'available',
        'qualifier': 'convergent',
        'agreements': <dynamic>[],
        'disagreements': [
          {'text': 'Désaccord pourtant présent.'},
        ],
        'cta': {'agreement': null, 'disagreement': null},
      });
      expect(block.qualifier, 'convergent');
    });

    test('pending : listes vides, isPending', () {
      final block = ConsensusBlock.fromJsonOrAbsent({
        'state': 'pending',
        'qualifier': null,
        'agreements': <dynamic>[],
        'disagreements': <dynamic>[],
        'cta': {'agreement': null, 'disagreement': null},
        'generated_at': null,
      });
      expect(block.isPending, isTrue);
      expect(block.isAvailable, isFalse);
      expect(block.agreements, isEmpty);
    });

    test('constat sans texte ou malformé → ignoré', () {
      final block = ConsensusBlock.fromJsonOrAbsent({
        'state': 'available',
        'agreements': [
          {'text': ''},
          'junk',
          {'support_count': 3},
          {'text': 'Seul constat valide.'},
        ],
      });
      expect(block.agreements.single.text, 'Seul constat valide.');
    });
  });

  group('DisplayGates', () {
    test('fromJson lit les 5 gates', () {
      final gates = DisplayGates.fromJson({
        'is_solo': false,
        'has_cta': true,
        'has_cards': true,
        'has_ai_card': false,
        'has_bar': true,
      });
      expect(gates.isSolo, isFalse);
      expect(gates.hasCta, isTrue);
      expect(gates.hasCards, isTrue);
      expect(gates.hasAiCard, isFalse);
      expect(gates.hasBar, isTrue);
    });

    test('hidden() : TOUT false, y compris isSolo', () {
      const gates = DisplayGates.hidden();
      expect(gates.isSolo, isFalse);
      expect(gates.hasCta, isFalse);
      expect(gates.hasCards, isFalse);
      expect(gates.hasAiCard, isFalse);
      expect(gates.hasBar, isFalse);
    });

    test('fromCoverageCount : parité avec compute_display_gates backend', () {
      // 1 média → solo, rien d'autre.
      final one = DisplayGates.fromCoverageCount(1);
      expect(one.isSolo, isTrue);
      expect(one.hasCta, isFalse);
      expect(one.hasCards, isFalse);
      expect(one.hasAiCard, isFalse);
      expect(one.hasBar, isFalse);

      // 2 médias → CTA + carrousel, sans carte IA ni barre.
      final two = DisplayGates.fromCoverageCount(2);
      expect(two.isSolo, isFalse);
      expect(two.hasCta, isTrue);
      expect(two.hasCards, isTrue);
      expect(two.hasAiCard, isFalse);
      expect(two.hasBar, isFalse);

      // 3+ → rendu complet.
      final three = DisplayGates.fromCoverageCount(3);
      expect(three.isSolo, isFalse);
      expect(three.hasCta, isTrue);
      expect(three.hasCards, isTrue);
      expect(three.hasAiCard, isTrue);
      expect(three.hasBar, isTrue);

      // 0 (défensif) → solo comme le backend (count <= 1).
      expect(DisplayGates.fromCoverageCount(0).isSolo, isTrue);
    });
  });

  group('PerspectivesResponse — blocs consensus/display', () {
    test('blocs présents → parsés', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'coverage_count': 4,
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
        'consensus': {
          'state': 'available',
          'qualifier': 'varied',
          'agreements': [
            {'text': 'Constat.'},
          ],
          'disagreements': <dynamic>[],
          'cta': {'agreement': null, 'disagreement': null},
        },
        'display': {
          'is_solo': false,
          'has_cta': true,
          'has_cards': true,
          'has_ai_card': true,
          'has_bar': true,
        },
      });
      expect(res.consensus.isAvailable, isTrue);
      expect(res.consensus.qualifier, 'varied');
      expect(res.display.hasAiCard, isTrue);
    });

    test('blocs absents (vieux backend, 200) → absent() + fallback gates', () {
      final res = PerspectivesResponse.fromJson(<String, dynamic>{
        'perspectives': <dynamic>[],
        'coverage_count': 3,
        'keywords': <dynamic>[],
        'bias_distribution': <String, dynamic>{},
      });
      expect(res.consensus.state, ConsensusBlock.stateUnavailable);
      // Fallback dérivé du coverage_count servi (3 → rendu complet).
      expect(res.display.hasAiCard, isTrue);
      expect(res.display.isSolo, isFalse);
    });

    test('chemin d\'erreur (réponse construite à la main) → gates hidden()', () {
      // C'est la réponse que fabriquent les deux catch (getPerspectives et
      // _fetchPerspectives) : une erreur réseau ne doit JAMAIS produire
      // isSolo == true (encart « seule rédaction » à tort).
      final res = PerspectivesResponse(
        perspectives: const [],
        keywords: const [],
        biasDistribution: const {},
      );
      expect(res.display.isSolo, isFalse);
      expect(res.display.hasCta, isFalse);
      expect(res.display.hasCards, isFalse);
      expect(res.consensus.state, ConsensusBlock.stateUnavailable);
    });
  });

  group('parseAnalyzeResponse', () {
    test('analysis présent, throttled absent → done implicite', () {
      final r = parseAnalyzeResponse({'analysis': 'Synthèse.'});
      expect(r.analysis, 'Synthèse.');
      expect(r.throttled, isFalse);
    });

    test('throttled true → pas d\'analyse, flag levé', () {
      final r = parseAnalyzeResponse({'analysis': null, 'throttled': true});
      expect(r.analysis, isNull);
      expect(r.throttled, isTrue);
    });

    test('payload vide → ni analyse ni throttle (erreur côté appelant)', () {
      final r = parseAnalyzeResponse(<String, dynamic>{});
      expect(r.analysis, isNull);
      expect(r.throttled, isFalse);
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
