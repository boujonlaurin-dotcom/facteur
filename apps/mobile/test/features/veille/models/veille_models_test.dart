import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config_dto.dart';
import 'package:facteur/features/veille/models/veille_delivery.dart';
import 'package:facteur/features/veille/models/veille_suggestion.dart';

void main() {
  group('VeilleDeliveryArticle.fromJson', () {
    test('parses required fields', () {
      final article = VeilleDeliveryArticle.fromJson({
        'content_id': 'c1',
        'source_id': 's1',
        'title': 'Titre',
        'url': 'https://example.test/a',
        'excerpt': 'Résumé',
        'published_at': '2026-05-01T07:00:00Z',
      });

      expect(article.contentId, 'c1');
      expect(article.sourceId, 's1');
      expect(article.title, 'Titre');
      expect(article.url, 'https://example.test/a');
      expect(article.excerpt, 'Résumé');
      expect(article.publishedAt.toUtc().hour, 7);
    });

    test('defaults excerpt to empty string when missing', () {
      final article = VeilleDeliveryArticle.fromJson({
        'content_id': 'c1',
        'source_id': 's1',
        'title': 'Titre',
        'url': 'https://example.test/a',
        'published_at': '2026-05-01T07:00:00Z',
      });

      expect(article.excerpt, '');
    });
  });

  group('VeilleDeliveryItem.fromJson', () {
    test('parses cluster + articles + why_it_matters', () {
      final item = VeilleDeliveryItem.fromJson({
        'cluster_id': 'cl1',
        'title': 'IA & écoles',
        'why_it_matters': 'Sujet structurant.',
        'articles': [
          {
            'content_id': 'c1',
            'source_id': 's1',
            'title': 'A1',
            'url': 'https://example.test/a1',
            'excerpt': 'e1',
            'published_at': '2026-05-01T07:00:00Z',
          },
        ],
      });

      expect(item.clusterId, 'cl1');
      expect(item.title, 'IA & écoles');
      expect(item.whyItMatters, 'Sujet structurant.');
      expect(item.articles, hasLength(1));
      expect(item.articles.first.contentId, 'c1');
    });

    test('handles empty articles list', () {
      final item = VeilleDeliveryItem.fromJson({
        'cluster_id': 'cl1',
        'title': 't',
        'why_it_matters': '',
        'articles': <dynamic>[],
      });
      expect(item.articles, isEmpty);
    });
  });

  group('VeilleDeliveryListItem.fromJson', () {
    test('parses target_date as DateTime + state enum', () {
      final item = VeilleDeliveryListItem.fromJson({
        'id': 'd1',
        'veille_config_id': 'vc1',
        'target_date': '2026-05-02',
        'generation_state': 'succeeded',
        'item_count': 5,
        'generated_at': '2026-05-02T07:30:00Z',
        'created_at': '2026-05-02T07:00:00Z',
      });

      expect(item.id, 'd1');
      expect(item.veilleConfigId, 'vc1');
      expect(item.generationState, VeilleGenerationState.succeeded);
      expect(item.itemCount, 5);
      expect(item.generatedAt, isNotNull);
    });

    test('null generated_at when missing', () {
      final item = VeilleDeliveryListItem.fromJson({
        'id': 'd1',
        'veille_config_id': 'vc1',
        'target_date': '2026-05-02',
        'generation_state': 'pending',
        'item_count': 0,
        'created_at': '2026-05-02T07:00:00Z',
      });
      expect(item.generatedAt, isNull);
      expect(item.generationState, VeilleGenerationState.pending);
    });
  });

  group('VeilleDeliveryResponse.fromJson', () {
    test('parses full response with items', () {
      final delivery = VeilleDeliveryResponse.fromJson({
        'id': 'd1',
        'veille_config_id': 'vc1',
        'target_date': '2026-05-02',
        'items': [
          {
            'cluster_id': 'cl1',
            'title': 'titre',
            'why_it_matters': 'why',
            'articles': <dynamic>[],
          },
        ],
        'generation_state': 'succeeded',
        'attempts': 1,
        'started_at': '2026-05-02T07:00:00Z',
        'finished_at': '2026-05-02T07:30:00Z',
        'last_error': null,
        'version': 1,
        'generated_at': '2026-05-02T07:30:00Z',
        'created_at': '2026-05-02T07:00:00Z',
        'updated_at': '2026-05-02T07:30:00Z',
      });

      expect(delivery.items, hasLength(1));
      expect(delivery.generationState, VeilleGenerationState.succeeded);
    });

    test('handles failed state with last_error', () {
      final delivery = VeilleDeliveryResponse.fromJson({
        'id': 'd1',
        'veille_config_id': 'vc1',
        'target_date': '2026-05-02',
        'items': <dynamic>[],
        'generation_state': 'failed',
        'attempts': 3,
        'started_at': '2026-05-02T07:00:00Z',
        'finished_at': null,
        'last_error': 'LLM timeout',
        'version': 1,
        'generated_at': null,
        'created_at': '2026-05-02T07:00:00Z',
        'updated_at': '2026-05-02T07:00:00Z',
      });

      expect(delivery.generationState, VeilleGenerationState.failed);
      expect(delivery.lastError, 'LLM timeout');
      expect(delivery.items, isEmpty);
    });
  });

  group('VeilleTopicSuggestion.fromJson', () {
    test('parses with optional reason', () {
      final s = VeilleTopicSuggestion.fromJson({
        'topic_id': 't-eval',
        'label': 'Évaluation',
        'reason': 'présent dans 8 lectures',
      });
      expect(s.topicId, 't-eval');
      expect(s.label, 'Évaluation');
      expect(s.reason, 'présent dans 8 lectures');
    });

    test('null reason when missing', () {
      final s = VeilleTopicSuggestion.fromJson({
        'topic_id': 't1',
        'label': 'X',
      });
      expect(s.reason, isNull);
    });
  });

  group('VeilleSourceSuggestionsResponse.fromJson', () {
    test('parses flat sources list with is_already_followed + relevance', () {
      final r = VeilleSourceSuggestionsResponse.fromJson({
        'sources': [
          {
            'source_id': 's1',
            'name': 'Le Monde',
            'url': 'https://lemonde.fr',
            'feed_url': 'https://lemonde.fr/rss',
            'theme': 'edu',
            'why': null,
            'is_already_followed': true,
            'relevance_score': 0.92,
          },
          {
            'source_id': 's2',
            'name': 'EdSurge',
            'url': 'https://edsurge.com',
            'feed_url': 'https://edsurge.com/rss',
            'theme': 'edu',
            'why': 'innovations US',
            'is_already_followed': false,
            'relevance_score': 0.7,
          },
        ],
      });
      expect(r.sources, hasLength(2));
      expect(r.sources.first.isAlreadyFollowed, isTrue);
      expect(r.sources.first.relevanceScore, 0.92);
      expect(r.sources[1].why, 'innovations US');
      expect(r.sources[1].isAlreadyFollowed, isFalse);
    });
  });

  group('VeilleConfigDto.fromJson', () {
    test('hydrates topics + sources', () {
      final cfg = VeilleConfigDto.fromJson({
        'id': 'vc1',
        'user_id': 'u1',
        'theme_id': 'edu',
        'theme_label': 'Éducation',
        'frequency': 'weekly',
        'day_of_week': 0,
        'delivery_hour': 7,
        'timezone': 'Europe/Paris',
        'status': 'active',
        'last_delivered_at': null,
        'next_scheduled_at': '2026-05-09T05:00:00Z',
        'created_at': '2026-05-02T07:00:00Z',
        'updated_at': '2026-05-02T07:00:00Z',
        'topics': [
          {
            'id': 't-row-1',
            'topic_id': 't-eval',
            'label': 'Évaluation',
            'kind': 'preset',
            'reason': null,
            'position': 0,
          },
        ],
        'sources': [
          {
            'id': 'vs1',
            'kind': 'followed',
            'why': null,
            'position': 0,
            'source': {
              'id': 's1',
              'name': 'Le Monde',
              'url': 'https://lemonde.fr',
              'feed_url': 'https://lemonde.fr/rss',
              'theme': 'edu',
              'type': 'article',
              'is_curated': true,
              'logo_url': null,
            },
          },
        ],
      });

      expect(cfg.id, 'vc1');
      expect(cfg.frequency, 'weekly');
      expect(cfg.dayOfWeek, 0);
      expect(cfg.topics, hasLength(1));
      expect(cfg.topics.first.label, 'Évaluation');
      expect(cfg.sources, hasLength(1));
      expect(cfg.sources.first.source.name, 'Le Monde');
    });
  });

  group('VeilleConfigUpsertRequest.toJson', () {
    test('serializes minimal weekly config', () {
      final body = VeilleConfigUpsertRequest(
        themeId: 'edu',
        themeLabel: 'Éducation',
        topics: const [
          VeilleTopicSelectionRequest(
            topicId: 't-eval',
            label: 'Évaluation',
            kind: 'preset',
          ),
        ],
        sourceSelections: const [
          VeilleSourceSelectionRequest(
            kind: 'followed',
            sourceId: 's1',
            position: 0,
          ),
        ],
        frequency: 'weekly',
        dayOfWeek: 0,
      );

      final json = body.toJson();
      expect(json['theme_id'], 'edu');
      expect(json['frequency'], 'weekly');
      expect(json['day_of_week'], 0);
      expect((json['topics'] as List).first['kind'], 'preset');
      expect((json['source_selections'] as List).first['source_id'], 's1');
    });

    test('serializes niche candidate when no source_id', () {
      final body = VeilleConfigUpsertRequest(
        themeId: 'edu',
        themeLabel: 'Éducation',
        topics: const [],
        sourceSelections: const [
          VeilleSourceSelectionRequest(
            kind: 'niche',
            nicheCandidate: VeilleNicheCandidateRequest(
              name: 'New niche',
              url: 'https://niche.test',
            ),
          ),
        ],
        frequency: 'monthly',
        dayOfWeek: null,
      );
      final json = body.toJson();
      final selections = json['source_selections'] as List;
      expect(selections.first['niche_candidate'], isNotNull);
      expect(selections.first.containsKey('source_id'), isFalse);
      expect(json.containsKey('day_of_week'), isFalse);
    });
  });

  group('VeilleConfigPatchRequest.toJson', () {
    test('omits null fields entirely', () {
      final body = VeilleConfigPatchRequest(status: 'paused');
      final json = body.toJson();
      expect(json, {'status': 'paused'});
    });
  });

  group('VeilleConfigUpsertRequest — purpose + brief (PR B)', () {
    test('omits keys absent → still includes null purpose/brief/preset', () {
      // Backwards compat : on envoie toujours les 4 clés (même null), pour
      // permettre au backend de les clear si l'utilisateur les efface.
      final body = VeilleConfigUpsertRequest(
        themeId: 'tech',
        themeLabel: 'Tech',
        topics: const [],
        sourceSelections: const [],
        frequency: 'weekly',
        dayOfWeek: 0,
      );
      final json = body.toJson();
      expect(json.containsKey('purpose'), isTrue);
      expect(json['purpose'], isNull);
      expect(json['purpose_other'], isNull);
      expect(json['editorial_brief'], isNull);
      expect(json['preset_id'], isNull);
    });

    test('serializes purpose + brief + preset_id', () {
      final body = VeilleConfigUpsertRequest(
        themeId: 'tech',
        themeLabel: 'Tech',
        topics: const [],
        sourceSelections: const [],
        frequency: 'weekly',
        dayOfWeek: 0,
        purpose: 'preparer_projet',
        editorialBrief: 'Plutôt analyses long format',
        presetId: 'ia_agentique',
      );
      final json = body.toJson();
      expect(json['purpose'], 'preparer_projet');
      expect(json['purpose_other'], isNull);
      expect(json['editorial_brief'], 'Plutôt analyses long format');
      expect(json['preset_id'], 'ia_agentique');
    });

    test('serializes purpose=autre with purpose_other', () {
      final body = VeilleConfigUpsertRequest(
        themeId: 'tech',
        themeLabel: 'Tech',
        topics: const [],
        sourceSelections: const [],
        frequency: 'weekly',
        dayOfWeek: 0,
        purpose: 'autre',
        purposeOther: 'Préparer un livre',
      );
      final json = body.toJson();
      expect(json['purpose'], 'autre');
      expect(json['purpose_other'], 'Préparer un livre');
    });
  });

  group('VeilleConfigDto.fromJson — purpose + brief (PR B)', () {
    test('parses purpose/purpose_other/editorial_brief/preset_id', () {
      final dto = VeilleConfigDto.fromJson({
        'id': 'cfg-1',
        'user_id': 'u-1',
        'theme_id': 'tech',
        'theme_label': 'Tech',
        'frequency': 'weekly',
        'day_of_week': 0,
        'delivery_hour': 7,
        'timezone': 'Europe/Paris',
        'status': 'active',
        'created_at': '2026-05-01T07:00:00Z',
        'updated_at': '2026-05-01T07:00:00Z',
        'topics': [],
        'sources': [],
        'purpose': 'preparer_projet',
        'purpose_other': null,
        'editorial_brief': 'Long format',
        'preset_id': 'ia_agentique',
      });
      expect(dto.purpose, 'preparer_projet');
      expect(dto.purposeOther, isNull);
      expect(dto.editorialBrief, 'Long format');
      expect(dto.presetId, 'ia_agentique');
    });

    test('handles missing purpose/brief fields gracefully', () {
      final dto = VeilleConfigDto.fromJson({
        'id': 'cfg-1',
        'user_id': 'u-1',
        'theme_id': 'tech',
        'theme_label': 'Tech',
        'frequency': 'weekly',
        'day_of_week': 0,
        'delivery_hour': 7,
        'timezone': 'Europe/Paris',
        'status': 'active',
        'created_at': '2026-05-01T07:00:00Z',
        'updated_at': '2026-05-01T07:00:00Z',
        'topics': [],
        'sources': [],
      });
      expect(dto.purpose, isNull);
      expect(dto.editorialBrief, isNull);
    });
  });
}
