import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/utils/closing_recap.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Fixtures
  // ---------------------------------------------------------------------------

  EssentielArticle essArticle(String id, {bool isRead = false}) =>
      EssentielArticle(
        contentId: id,
        title: 't',
        url: 'https://x.test/$id',
        publishedAt: DateTime(2026, 1, 1),
        sourceName: 'S',
        sourceLetter: 'S',
        sectionLabel: '',
        rank: 1,
        isRead: isRead,
      );

  EssentielSection essentielSection(List<EssentielArticle> articles) =>
      EssentielSection(articles: articles, label: 'L’Essentiel du jour');

  DigestTopicSection digestSection(
    String label,
    List<DigestItem> articles,
  ) =>
      DigestTopicSection(
        kind: SectionKind.essentiel,
        label: label,
        accent: const Color(0xFFB0470A),
        coreVisibleCount: 3,
        topics: [
          DigestTopic(topicId: 't', label: label, articles: articles),
        ],
      );

  DigestItem digestItem(String id, {bool isRead = false}) =>
      DigestItem(contentId: id, title: 't', isRead: isRead);

  Content content(
    String id, {
    ContentStatus status = ContentStatus.unseen,
    int readingProgress = 0,
  }) =>
      Content(
        id: id,
        title: 't',
        url: 'https://x.test/$id',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 1, 1),
        source: Source(id: 's', name: 'S', type: SourceType.article),
        status: status,
        readingProgress: readingProgress,
      );

  FeedThemeSection themeSection(String label, List<Content> items) =>
      FeedThemeSection(
        kind: SectionKind.theme,
        label: label,
        accent: const Color(0xFF2C3E50),
        coreVisibleCount: 3,
        themeSlug: 'tech',
        items: items,
      );

  // ---------------------------------------------------------------------------
  // buildClosingRecap
  // ---------------------------------------------------------------------------

  group('buildClosingRecap', () {
    test('counts Essentiel articles read via isRead', () {
      final recaps = buildClosingRecap(
        sections: [
          essentielSection([
            essArticle('a', isRead: true),
            essArticle('b'),
            essArticle('c', isRead: true),
          ]),
        ],
        consumedIds: const {},
      );
      expect(recaps, [(label: 'L’Essentiel du jour', count: 2)]);
    });

    test('counts articles read via consumedIds (session-level)', () {
      final recaps = buildClosingRecap(
        sections: [
          essentielSection([essArticle('a'), essArticle('b')]),
        ],
        consumedIds: const {'a'},
      );
      expect(recaps.single.count, 1);
    });

    test('counts digest topic articles flattened across topics', () {
      final recaps = buildClosingRecap(
        sections: [
          digestSection('Actus du jour', [
            digestItem('a', isRead: true),
            digestItem('b'),
          ]),
        ],
        consumedIds: const {},
      );
      expect(recaps.single, (label: 'Actus du jour', count: 1));
    });

    test('counts feed content via consumed status / readingProgress / ids', () {
      final recaps = buildClosingRecap(
        sections: [
          themeSection('Tech', [
            content('a', status: ContentStatus.consumed),
            content('b', readingProgress: 30),
            content('c'),
            content('d'),
          ]),
        ],
        consumedIds: const {'d'},
      );
      expect(recaps.single, (label: 'Tech', count: 3));
    });

    test('drops sections with zero read and sorts by count desc', () {
      final recaps = buildClosingRecap(
        sections: [
          themeSection('Tech', [content('a', readingProgress: 10)]),
          digestSection('Actus du jour', [
            digestItem('x', isRead: true),
            digestItem('y', isRead: true),
          ]),
          essentielSection([essArticle('z')]), // 0 read → dropped
        ],
        consumedIds: const {},
      );
      expect(recaps, [
        (label: 'Actus du jour', count: 2),
        (label: 'Tech', count: 1),
      ]);
    });
  });

  // ---------------------------------------------------------------------------
  // formatClosingRecap
  // ---------------------------------------------------------------------------

  group('formatClosingRecap', () {
    test('empty → null (fallback to step label)', () {
      expect(formatClosingRecap(const []), isNull);
    });

    test('one section uses the gendered article', () {
      expect(
        formatClosingRecap(const [(label: 'Tech', count: 4)]),
        'Tu as lu sur la Tech (4).',
      );
    });

    test('two sections joined with « et » (no comma)', () {
      expect(
        formatClosingRecap(const [
          (label: 'Tech', count: 4),
          (label: 'Politique', count: 2),
        ]),
        'Tu as lu sur la Tech (4) et la Politique (2).',
      );
    });

    test('three sections use commas + « , et » before the last', () {
      expect(
        formatClosingRecap(const [
          (label: 'Tech', count: 4),
          (label: 'Politique', count: 2),
          (label: 'Actus du jour', count: 5),
        ]),
        'Tu as lu sur la Tech (4), la Politique (2), et l’Actu du jour (5).',
      );
    });

    test('known special labels map to elided/plural articles', () {
      expect(
        formatClosingRecap(const [(label: 'L’Essentiel du jour', count: 3)]),
        'Tu as lu sur l’Essentiel du jour (3).',
      );
      expect(
        formatClosingRecap(const [(label: 'Bonnes nouvelles', count: 1)]),
        'Tu as lu sur les Bonnes nouvelles (1).',
      );
    });

    test('unknown label falls back to raw label without article', () {
      expect(
        formatClosingRecap(const [(label: 'Mon sujet perso', count: 2)]),
        'Tu as lu sur Mon sujet perso (2).',
      );
    });
  });
}
