import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/utils/notif_teasers.dart';
import 'package:flutter_test/flutter_test.dart';

EssentielArticle _article({
  required String id,
  required String title,
  required int rank,
}) =>
    EssentielArticle(
      contentId: id,
      title: title,
      url: 'https://x.test/$id',
      publishedAt: DateTime(2026, 1, 1),
      sourceName: 'S',
      sourceLetter: 'S',
      sectionLabel: 'Essentiel',
      rank: rank,
    );

DigestTopic _topic({
  required String label,
  required int rank,
  List<String> articleTitles = const [],
}) =>
    DigestTopic(
      topicId: 'topic-$label-$rank',
      label: label,
      rank: rank,
      articles: [
        for (var i = 0; i < articleTitles.length; i++)
          DigestItem(contentId: '$label-$i', title: articleTitles[i]),
      ],
    );

DigestResponse _digest(List<DigestTopic> topics) => DigestResponse(
      digestId: 'd1',
      userId: 'u1',
      targetDate: DateTime(2026, 1, 1),
      generatedAt: DateTime(2026, 1, 1),
      topics: topics,
    );

void main() {
  group('buildEssentielTeasers', () {
    test('returns top 3 titles ordered by rank ascending', () {
      final teasers = buildEssentielTeasers([
        _article(id: 'c', title: 'Climat', rank: 3),
        _article(id: 'a', title: 'Trump', rank: 1),
        _article(id: 'b', title: 'Marseille', rank: 2),
        _article(id: 'd', title: 'Quatrième', rank: 4),
      ]);
      expect(teasers, ['Trump', 'Marseille', 'Climat']);
    });

    test('empty input → empty list', () {
      expect(buildEssentielTeasers(const []), isEmpty);
    });

    test('drops blank titles and trims', () {
      final teasers = buildEssentielTeasers([
        _article(id: 'a', title: '  Trump  ', rank: 1),
        _article(id: 'b', title: '   ', rank: 2),
        _article(id: 'c', title: 'Climat', rank: 3),
      ]);
      expect(teasers, ['Trump', 'Climat']);
    });

    test('dedups case-insensitively, first occurrence wins', () {
      final teasers = buildEssentielTeasers([
        _article(id: 'a', title: 'Trump', rank: 1),
        _article(id: 'b', title: 'trump', rank: 2),
        _article(id: 'c', title: 'Climat', rank: 3),
      ]);
      expect(teasers, ['Trump', 'Climat']);
    });

    test('fewer than 3 items → renders what is available', () {
      final teasers = buildEssentielTeasers([
        _article(id: 'a', title: 'Trump', rank: 1),
      ]);
      expect(teasers, ['Trump']);
    });
  });

  group('buildGoodNewsTeasers', () {
    test('null digest → empty list', () {
      expect(buildGoodNewsTeasers(null), isEmpty);
    });

    test('returns top 3 labels ordered by rank ascending', () {
      final teasers = buildGoodNewsTeasers(_digest([
        _topic(label: 'Solidarité', rank: 2),
        _topic(label: 'Avancée médicale', rank: 1),
        _topic(label: 'Climat positif', rank: 3),
        _topic(label: 'Quatrième', rank: 4),
      ]));
      expect(teasers, ['Avancée médicale', 'Solidarité', 'Climat positif']);
    });

    test('falls back to first article title when label is blank', () {
      final teasers = buildGoodNewsTeasers(_digest([
        _topic(label: '   ', rank: 1, articleTitles: ['Une bonne nouvelle']),
      ]));
      expect(teasers, ['Une bonne nouvelle']);
    });

    test('topic with blank label and no article is dropped', () {
      final teasers = buildGoodNewsTeasers(_digest([
        _topic(label: '', rank: 1),
        _topic(label: 'Espoir', rank: 2),
      ]));
      expect(teasers, ['Espoir']);
    });

    test('all topics empty → empty list', () {
      final teasers = buildGoodNewsTeasers(_digest([
        _topic(label: '', rank: 1),
      ]));
      expect(teasers, isEmpty);
    });
  });

  group('sanitizeTeasers', () {
    test('trims, drops empty, dedups, caps at 3', () {
      final result = sanitizeTeasers([
        ' A ',
        'a',
        '',
        '   ',
        'B',
        'C',
        'D',
      ]);
      expect(result, ['A', 'B', 'C']);
    });
  });
}
