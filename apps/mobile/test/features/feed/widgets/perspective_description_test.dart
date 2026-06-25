import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/repositories/feed_repository.dart'
    show PerspectiveData;
import 'package:facteur/features/feed/widgets/perspectives_bottom_sheet.dart';

void main() {
  group('Perspective.fromJson description', () {
    test('parse le champ description quand présent', () {
      final p = Perspective.fromJson(const {
        'title': 'Titre',
        'url': 'https://ex.com/a',
        'source_name': 'Le Monde',
        'source_domain': 'lemonde.fr',
        'bias_stance': 'center',
        'description': 'Un chapô explicatif.',
      });
      expect(p.description, 'Un chapô explicatif.');
    });

    test('description null quand absente (rétro-compat cache)', () {
      final p = Perspective.fromJson(const {
        'title': 'Titre',
        'url': 'https://ex.com/a',
        'source_name': 'Le Monde',
        'source_domain': 'lemonde.fr',
        'bias_stance': 'center',
      });
      expect(p.description, isNull);
    });
  });

  group('PerspectiveData.fromJson description', () {
    test('parse le champ description quand présent', () {
      final p = PerspectiveData.fromJson(const {
        'title': 'Titre',
        'url': 'https://ex.com/a',
        'source_name': 'Le Monde',
        'source_domain': 'lemonde.fr',
        'bias_stance': 'center',
        'description': 'Chapô.',
      });
      expect(p.description, 'Chapô.');
    });
  });

  group('Perspective.toPreviewContent', () {
    test('mappe description, source synthétique et favicon', () {
      final p = Perspective(
        title: 'Titre',
        url: 'https://ex.com/article',
        sourceName: 'Le Monde',
        sourceDomain: 'lemonde.fr',
        biasStance: 'center',
        publishedAt: '2026-06-20T10:00:00Z',
        description: 'Un chapô.',
      );
      final content = p.toPreviewContent();

      expect(content.title, 'Titre');
      expect(content.url, 'https://ex.com/article');
      expect(content.description, 'Un chapô.');
      expect(content.source.name, 'Le Monde');
      expect(content.source.logoUrl, contains('domain=lemonde.fr'));
      expect(content.thumbnailUrl, isNull);
      expect(content.publishedAt.toUtc().year, 2026);
    });

    test('logo null si domaine vide ; date repli si non parsable', () {
      final p = Perspective(
        title: 'Titre',
        url: 'https://ex.com/article',
        sourceName: 'Inconnu',
        sourceDomain: '',
        biasStance: 'unknown',
        publishedAt: 'pas-une-date',
      );
      final content = p.toPreviewContent();

      expect(content.source.logoUrl, isNull);
      // Date non parsable → repli sur "maintenant" (pas de crash).
      expect(content.publishedAt, isNotNull);
    });
  });
}
