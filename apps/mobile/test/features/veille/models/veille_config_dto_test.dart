import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config_dto.dart';

/// Round-trip des DTO veille touchés par PR-3 : suggestion d'angles LLM
/// (`VeilleAngleSuggestionDto` / `VeilleSuggestAnglesResponse`) + la grappe
/// `keywords` sur les topics (contrat livré par #730, exercé ici côté angle).
void main() {
  group('VeilleAngleSuggestionDto.fromJson', () {
    test('mappe title / keywords / reason', () {
      final dto = VeilleAngleSuggestionDto.fromJson(const {
        'title': 'IA générative',
        'keywords': ['ia', 'llm', 'chatgpt'],
        'reason': 'Impact workflows',
      });
      expect(dto.title, 'IA générative');
      expect(dto.keywords, ['ia', 'llm', 'chatgpt']);
      expect(dto.reason, 'Impact workflows');
    });

    test('keywords absents → liste vide ; reason absent → null', () {
      final dto = VeilleAngleSuggestionDto.fromJson(const {
        'title': 'Sans grappe',
      });
      expect(dto.keywords, isEmpty);
      expect(dto.reason, isNull);
    });
  });

  group('VeilleSuggestAnglesResponse.fromJson', () {
    test('mappe la liste d\'angles', () {
      final res = VeilleSuggestAnglesResponse.fromJson(const {
        'angles': [
          {
            'title': 'Régulation',
            'keywords': ['ai act'],
            'reason': null,
          },
          {'title': 'Open source', 'keywords': <String>[]},
        ],
      });
      expect(res.angles.length, 2);
      expect(res.angles.first.title, 'Régulation');
      expect(res.angles.first.keywords, ['ai act']);
      expect(res.angles[1].reason, isNull);
    });

    test('clé angles absente → liste vide (pas de crash)', () {
      expect(VeilleSuggestAnglesResponse.fromJson(const {}).angles, isEmpty);
    });
  });

  group('VeilleTopicDto / VeilleTopicSelectionRequest — grappe keywords', () {
    test('VeilleTopicDto.fromJson lit keywords (round-trip backend)', () {
      final dto = VeilleTopicDto.fromJson(const {
        'id': 't1',
        'topic_id': 'angle-ia',
        'label': 'IA',
        'kind': 'suggested',
        'reason': null,
        'position': 0,
        'keywords': ['llm', 'agents'],
      });
      expect(dto.keywords, ['llm', 'agents']);
    });

    test('keywords absents → liste vide par défaut', () {
      final dto = VeilleTopicDto.fromJson(const {
        'id': 't1',
        'topic_id': 'preset-ai',
        'label': 'IA',
        'kind': 'preset',
        'position': 0,
      });
      expect(dto.keywords, isEmpty);
    });

    test('VeilleTopicSelectionRequest.toJson sérialise keywords', () {
      const req = VeilleTopicSelectionRequest(
        topicId: 'angle-ia',
        label: 'IA générative',
        kind: 'suggested',
        keywords: ['ia', 'llm'],
      );
      expect(req.toJson()['keywords'], ['ia', 'llm']);
    });
  });

  group('VeilleResolvedTopicDto.fromJson', () {
    test('mappe label, topic_id, keywords, description et metadata', () {
      final dto = VeilleResolvedTopicDto.fromJson(const {
        'label': 'Musées contemporains de Barcelone',
        'topic_id': 'custom-musees-contemporains-de-barcelone',
        'keywords': ['macba', 'exposition'],
        'description': 'Suivi des expositions',
        'metadata': {'slug_parent': 'culture', 'entity_type': 'LOCATION'},
      });
      expect(dto.label, 'Musées contemporains de Barcelone');
      expect(dto.topicId, 'custom-musees-contemporains-de-barcelone');
      expect(dto.keywords, ['macba', 'exposition']);
      expect(dto.description, 'Suivi des expositions');
      expect(dto.metadata['slug_parent'], 'culture');
    });
  });

  group('VeilleSuggestSourcesResponse.fromJson', () {
    test('mappe les candidats sources', () {
      final res = VeilleSuggestSourcesResponse.fromJson(const {
        'sources': [
          {
            'name': 'MACBA',
            'url': 'https://www.macba.cat',
            'why': 'Musée officiel',
            'relevance_score': 1.0,
          },
        ],
      });
      expect(res.sources.length, 1);
      expect(res.sources.first.name, 'MACBA');
      expect(res.sources.first.url, 'https://www.macba.cat');
      expect(res.sources.first.why, 'Musée officiel');
      expect(res.sources.first.relevanceScore, 1.0);
    });

    test('clé sources absente → liste vide', () {
      expect(VeilleSuggestSourcesResponse.fromJson(const {}).sources, isEmpty);
    });
  });

  group('VeilleConfigDto.fromJson — unconnected_sources', () {
    Map<String, dynamic> baseConfig() => {
          'id': 'cfg-1',
          'user_id': 'user-1',
          'theme_id': 'tech',
          'theme_label': 'Tech',
          'status': 'active',
          'created_at': '2026-06-04T00:00:00Z',
          'updated_at': '2026-06-04T00:00:00Z',
          'topics': const <dynamic>[],
          'sources': const <dynamic>[],
          'keywords': const <dynamic>[],
        };

    test('mappe url + reason des sources non connectées', () {
      final dto = VeilleConfigDto.fromJson({
        ...baseConfig(),
        'unconnected_sources': const [
          {
            'client_slug': 'niche-exemple',
            'name': 'Exemple',
            'url': 'https://exemple.test',
            'reason': 'Aucun flux RSS.',
          },
        ],
      });
      expect(dto.unconnectedSources, hasLength(1));
      expect(dto.unconnectedSources.first.clientSlug, 'niche-exemple');
      expect(dto.unconnectedSources.first.name, 'Exemple');
      expect(dto.unconnectedSources.first.url, 'https://exemple.test');
      expect(dto.unconnectedSources.first.reason, 'Aucun flux RSS.');
    });

    test('clé absente → liste vide (rétro-compat backend non déployé)', () {
      expect(
        VeilleConfigDto.fromJson(baseConfig()).unconnectedSources,
        isEmpty,
      );
    });
  });

  group('VeilleResolveSourceCandidatesResponseDto.fromJson', () {
    test('mappe resolved + failed', () {
      final dto = VeilleResolveSourceCandidatesResponseDto.fromJson(const {
        'resolved': [
          {
            'client_slug': 'niche-macba',
            'source_id': 'src-1',
            'name': 'MACBA',
            'url': 'https://www.macba.cat',
            'feed_url': 'https://www.macba.cat/feed.xml',
            'logo_url': 'https://logo.test/macba.png',
            'description': 'Musée',
          },
        ],
        'failed': [
          {
            'client_slug': 'niche-ko',
            'name': 'KO',
            'url': 'https://ko.test',
            'reason': 'Aucun flux RSS.',
          },
        ],
      });
      expect(dto.resolved.single.clientSlug, 'niche-macba');
      expect(dto.resolved.single.sourceId, 'src-1');
      expect(dto.resolved.single.feedUrl, 'https://www.macba.cat/feed.xml');
      expect(dto.failed.single.clientSlug, 'niche-ko');
      expect(dto.failed.single.reason, 'Aucun flux RSS.');
    });
  });
}
