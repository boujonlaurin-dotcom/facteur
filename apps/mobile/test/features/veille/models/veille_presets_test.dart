import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/veille/models/veille_config.dart';

void main() {
  group('VeillePreset.fromJson', () {
    test('parses full payload including sources', () {
      final preset = VeillePreset.fromJson({
        'slug': 'ia_agentique',
        'label': 'Outils IA agentique',
        'accroche': 'Les derniers outils IA',
        'theme_id': 'tech',
        'theme_label': 'Technologie',
        'topics': ['A', 'B'],
        'purposes': ['progresser_au_travail'],
        'editorial_brief': 'brief',
        'sources': [
          {
            'id': '11111111-1111-1111-1111-111111111111',
            'name': 'Source A',
            'url': 'https://a.example.com',
            'logo_url': 'https://logo.example.com/a.png',
          },
        ],
      });

      expect(preset.slug, 'ia_agentique');
      expect(preset.themeLabel, 'Technologie');
      expect(preset.topics, ['A', 'B']);
      expect(preset.purposes, ['progresser_au_travail']);
      expect(preset.sources.length, 1);
      expect(preset.sources.first.logoUrl, 'https://logo.example.com/a.png');
    });

    test('handles missing optional fields with safe defaults', () {
      final preset = VeillePreset.fromJson({
        'slug': 's',
        'label': 'L',
        'accroche': 'A',
        'theme_id': 'tech',
        'theme_label': 'Tech',
      });

      expect(preset.topics, isEmpty);
      expect(preset.purposes, isEmpty);
      expect(preset.editorialBrief, '');
      expect(preset.sources, isEmpty);
    });
  });
}
