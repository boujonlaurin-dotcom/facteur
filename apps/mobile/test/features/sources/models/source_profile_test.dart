import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/sources/models/source_profile.dart';

void main() {
  group('ThemeShare.fromJson', () {
    test('parse theme / count / share', () {
      final t = ThemeShare.fromJson({
        'theme': 'politics',
        'count': 12,
        'share': 0.4,
      });
      expect(t.theme, 'politics');
      expect(t.count, 12);
      expect(t.share, 0.4);
    });

    test('défauts sûrs si champs manquants', () {
      final t = ThemeShare.fromJson(<String, dynamic>{});
      expect(t.theme, 'autres');
      expect(t.count, 0);
      expect(t.share, 0.0);
    });
  });

  group('SourceProfile.fromJson', () {
    test('payload complet, dont recent_articles parsés en Content', () {
      final json = <String, dynamic>{
        'articles_30d': 40,
        'oldest_content_at': '2026-01-01T00:00:00Z',
        'theme_distribution': [
          {'theme': 'politics', 'count': 30, 'share': 0.75},
          {'theme': 'autres', 'count': 10, 'share': 0.25},
        ],
        'recent_articles': [
          {
            'id': 'a1',
            'title': 'Titre A',
            'url': 'https://example.com/a1',
            'content_type': 'article',
            'published_at': '2026-06-14T08:00:00Z',
            'is_followed_source': true,
            'source': {
              'id': 's1',
              'name': 'Le Monde',
              'logo_url': null,
              'type': 'article',
              'theme': 'politics',
            },
          },
        ],
      };

      final p = SourceProfile.fromJson(json);
      expect(p.articles30d, 40);
      expect(p.oldestContentAt, DateTime.utc(2026, 1, 1));
      expect(p.hasCoverage, isTrue);
      expect(p.themeDistribution.map((t) => t.theme), ['politics', 'autres']);
      expect(p.themeDistribution.first.share, 0.75);

      expect(p.hasArticles, isTrue);
      expect(p.recentArticles, hasLength(1));
      final article = p.recentArticles.first;
      expect(article.id, 'a1');
      expect(article.title, 'Titre A');
      expect(article.source.name, 'Le Monde');
      expect(article.isFollowedSource, isTrue);
    });

    test('payload vide → profil vide', () {
      final p = SourceProfile.fromJson(<String, dynamic>{});
      expect(p.articles30d, 0);
      expect(p.oldestContentAt, isNull);
      expect(p.themeDistribution, isEmpty);
      expect(p.recentArticles, isEmpty);
      expect(p.hasCoverage, isFalse);
      expect(p.hasArticles, isFalse);
    });
  });
}
