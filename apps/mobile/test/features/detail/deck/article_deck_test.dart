import 'package:flutter/material.dart' show Color;
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/detail/deck/models/article_deck.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/sources/models/source_model.dart';

Content _content(String id) => Content(
      id: id,
      title: 'title-$id',
      url: 'https://x.test/$id',
      contentType: ContentType.article,
      publishedAt: DateTime(2026, 1, 1),
      source: Source(id: 's', name: 'S', type: SourceType.article),
    );

FeedThemeSection _themeSection({int items = 8, int coreVisibleCount = 2}) {
  return FeedThemeSection(
    kind: SectionKind.theme,
    label: 'Tech',
    accent: const Color(0xFF2C3E50),
    coreVisibleCount: coreVisibleCount,
    themeSlug: 'tech',
    items: List.generate(items, (i) => _content('c$i')),
  );
}

void main() {
  group('articleDeckFromContents', () {
    test('positionne le deck sur l’article tapé', () {
      final deck = articleDeckFromContents(
        [_content('a'), _content('b'), _content('c')],
        'b',
        sectionKey: 'theme:tech',
        sectionLabel: 'Tech',
      );

      expect(deck, isNotNull);
      expect(deck!.initialIndex, 1);
      expect(deck.initialArticle.id, 'b');
      expect(deck.isNavigable, isTrue);
      expect(deck.sectionKey, 'theme:tech');
      expect(deck.sectionLabel, 'Tech');
    });

    test('déduplique par id en conservant le premier passage', () {
      final deck = articleDeckFromContents(
        [_content('a'), _content('b'), _content('a'), _content('c')],
        'c',
        sectionKey: 'k',
        sectionLabel: 'L',
      );

      expect(deck!.articles.map((a) => a.id), ['a', 'b', 'c']);
      expect(deck.initialIndex, 2);
    });

    test('ignore les articles sans id', () {
      final deck = articleDeckFromContents(
        [_content(''), _content('a'), _content('b')],
        'a',
        sectionKey: 'k',
        sectionLabel: 'L',
      );

      expect(deck!.articles.map((a) => a.id), ['a', 'b']);
      expect(deck.initialIndex, 0);
    });

    test('null quand l’article tapé n’est pas dans la liste', () {
      final deck = articleDeckFromContents(
        [_content('a'), _content('b')],
        'absent',
        sectionKey: 'k',
        sectionLabel: 'L',
      );

      expect(deck, isNull);
    });

    test('null sur une liste d’un seul article — rien à enchaîner', () {
      final deck = articleDeckFromContents(
        [_content('a')],
        'a',
        sectionKey: 'k',
        sectionLabel: 'L',
      );

      expect(deck, isNull);
    });

    test('le repère de position est désactivable (feed ouvert)', () {
      final deck = articleDeckFromContents(
        [_content('a'), _content('b')],
        'a',
        sectionKey: 'flaner',
        sectionLabel: 'Flâner',
        showPositionIndicator: false,
      );

      expect(deck!.showPositionIndicator, isFalse);
    });
  });

  group('articleDeckFromSection', () {
    test(
      'porte la section ENTIÈRE, pas l’aperçu borné par coreVisibleCount',
      () {
        // C’est le cœur de la feature : la Tournée n’affiche que 2 cartes,
        // le deck doit permettre d’atteindre les 6 autres, celles qui ne
        // sont visibles qu’en passant par « Tout lire ».
        final section = _themeSection(items: 8, coreVisibleCount: 2);
        final deck = articleDeckFromSection(section, 'c1');

        expect(deck!.articles, hasLength(8));
        expect(deck.initialIndex, 1);
        // Depuis la 2ᵉ carte affichée, l’article suivant est bien le 3ᵉ
        // article disponible — celui que l’aperçu masquait.
        expect(deck.articles[deck.initialIndex + 1].id, 'c2');
      },
    );

    test('EssentielSection — les articles du héros, dans l’ordre', () {
      final section = EssentielSection(
        articles: List.generate(
          5,
          (i) => EssentielArticle(
            contentId: 'e$i',
            title: 'Essentiel $i',
            url: 'https://x.test/e$i',
            publishedAt: DateTime(2026, 1, 1),
            sourceName: 'S',
            sourceLetter: 'S',
            sectionLabel: 'Politique',
            rank: i + 1,
          ),
        ),
      );

      final deck = articleDeckFromSection(section, 'e3');

      expect(deck!.articles.map((a) => a.id), ['e0', 'e1', 'e2', 'e3', 'e4']);
      expect(deck.initialIndex, 3);
      expect(deck.sectionKey, 'essentiel_v3');
    });

    test('DigestTopicSection — un article par sujet (le lead)', () {
      final section = DigestTopicSection(
        kind: SectionKind.bonnes,
        label: 'Bonnes Nouvelles',
        accent: const Color(0xFFD35400),
        coreVisibleCount: 2,
        topics: List.generate(
          4,
          (i) => DigestTopic(
            topicId: 't$i',
            label: 'Topic $i',
            articles: [DigestItem(contentId: 'c$i', title: 'A$i')],
          ),
        ),
      );

      final deck = articleDeckFromSection(section, 'c2');

      expect(deck!.articles.map((a) => a.id), ['c0', 'c1', 'c2', 'c3']);
      expect(deck.initialIndex, 2);
      expect(deck.sectionLabel, 'Bonnes Nouvelles');
    });

    test('DigestTopicSection — un sujet sans article ne casse pas le deck', () {
      final section = DigestTopicSection(
        kind: SectionKind.bonnes,
        label: 'Bonnes Nouvelles',
        accent: const Color(0xFFD35400),
        coreVisibleCount: 2,
        topics: [
          DigestTopic(
            topicId: 't0',
            label: 'Topic 0',
            articles: [DigestItem(contentId: 'c0', title: 'A0')],
          ),
          DigestTopic(topicId: 't1', label: 'Vide', articles: const []),
          DigestTopic(
            topicId: 't2',
            label: 'Topic 2',
            articles: [DigestItem(contentId: 'c2', title: 'A2')],
          ),
        ],
      );

      final deck = articleDeckFromSection(section, 'c0');

      expect(deck!.articles.map((a) => a.id), ['c0', 'c2']);
    });

    test('AlertsSection — aucun article, donc aucun deck', () {
      final section = AlertsSection(items: const []);
      expect(articleDeckFromSection(section, 'x'), isNull);
    });
  });
}
