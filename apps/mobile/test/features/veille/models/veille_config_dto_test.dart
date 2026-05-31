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
      final dto =
          VeilleAngleSuggestionDto.fromJson(const {'title': 'Sans grappe'});
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
      expect(
          VeilleSuggestAnglesResponse.fromJson(const {}).angles, isEmpty);
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
}
