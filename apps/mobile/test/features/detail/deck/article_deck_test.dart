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

    test('aucune suite de section hors tournée (feed ouvert)', () {
      final deck = articleDeckFromContents(
        [_content('a'), _content('b')],
        'a',
        sectionKey: 'flaner',
        sectionLabel: 'Flâner',
      );

      expect(deck!.nextSectionDeck, isNull);
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

  group('tourneeArticleDeck — enchaînement des sections', () {
    FeedThemeSection theme(String slug, String label, List<String> ids) {
      return FeedThemeSection(
        kind: SectionKind.theme,
        label: label,
        accent: const Color(0xFF2C3E50),
        coreVisibleCount: 2,
        themeSlug: slug,
        items: ids.map(_content).toList(),
      );
    }

    test('le dernier article mène au premier de la section suivante', () {
      final tech = theme('tech', 'Tech', ['a', 'b']);
      final eco = theme('eco', 'Économie', ['c', 'd', 'e']);
      final deck = tourneeArticleDeck([tech, eco], tech, 'a');

      expect(deck!.sectionKey, 'theme:tech');
      final next = deck.nextSectionDeck!();
      expect(next!.sectionLabel, 'Économie');
      expect(next.initialIndex, 0);
      expect(next.initialArticle.id, 'c');
    });

    test('la chaîne se poursuit de section en section', () {
      final s1 = theme('a', 'A', ['a1', 'a2']);
      final s2 = theme('b', 'B', ['b1', 'b2']);
      final s3 = theme('c', 'C', ['c1', 'c2']);
      final deck = tourneeArticleDeck([s1, s2, s3], s1, 'a1');

      final second = deck!.nextSectionDeck!();
      expect(second!.sectionLabel, 'B');
      final third = second.nextSectionDeck!();
      expect(third!.sectionLabel, 'C');
      // Fin de tournée : plus de suite, le deck s’arrête là.
      expect(third.nextSectionDeck, isNull);
    });

    test('saute les sections qui ne rendent aucun article', () {
      final tech = theme('tech', 'Tech', ['a', 'b']);
      final alerts = AlertsSection(items: const []);
      final eco = theme('eco', 'Économie', ['c', 'd']);
      final deck = tourneeArticleDeck([tech, alerts, eco], tech, 'a');

      expect(deck!.nextSectionDeck!()!.sectionLabel, 'Économie');
    });

    test('une section d’un seul article reste une étape de lecture', () {
      // Sans suite, un article seul ne fait pas un deck ; avec une suite, si :
      // c’est elle qui porte la navigation.
      final tech = theme('tech', 'Tech', ['a', 'b']);
      final solo = theme('solo', 'Solo', ['x']);
      final eco = theme('eco', 'Économie', ['c', 'd']);
      final deck = tourneeArticleDeck([tech, solo, eco], tech, 'a');

      final next = deck!.nextSectionDeck!();
      expect(next!.articles.map((a) => a.id), ['x']);
      expect(next.isNavigable, isTrue);
      expect(next.nextSectionDeck!()!.sectionLabel, 'Économie');
    });

    test('dernière section de la tournée — pas de suite', () {
      final tech = theme('tech', 'Tech', ['a', 'b']);
      final eco = theme('eco', 'Économie', ['c', 'd']);
      final deck = tourneeArticleDeck([tech, eco], eco, 'c');

      expect(deck!.nextSectionDeck, isNull);
    });

    test('section hors tournée — deck simple, sans chaînage', () {
      // Vue lettre / agrégat hebdo : la section n’est pas dans le snapshot
      // ordonné, il n’y a pas d’ordre où chercher une suite.
      final tech = theme('tech', 'Tech', ['a', 'b']);
      final horsTournee = theme('hebdo', 'Hebdo', ['h1', 'h2']);
      final deck = tourneeArticleDeck([tech], horsTournee, 'h1');

      expect(deck!.sectionLabel, 'Hebdo');
      expect(deck.nextSectionDeck, isNull);
    });

    test('chaque étape est notifiée, à toute profondeur de chaîne', () {
      // C’est ce fil qui permet à la Tournée de se rouvrir sur la section où la
      // lecture s’est arrêtée, et pas sur celle d’où l’on était parti.
      final s1 = theme('a', 'A', ['a1', 'a2']);
      final s2 = theme('b', 'B', ['b1', 'b2']);
      final s3 = theme('c', 'C', ['c1', 'c2']);
      final steps = <String>[];
      final deck = tourneeArticleDeck(
        [s1, s2, s3],
        s1,
        'a1',
        onSectionAdvanced: (next) => steps.add(next.sectionKey),
      );

      final second = deck!.nextSectionDeck!()!;
      second.onSectionAdvanced!(second);
      final third = second.nextSectionDeck!()!;
      third.onSectionAdvanced!(third);

      expect(steps, ['theme:b', 'theme:c']);
    });

    test('porte la section entière, comme le deck simple', () {
      final section = _themeSection(items: 8, coreVisibleCount: 2);
      final deck = tourneeArticleDeck([section], section, 'c1');

      expect(deck!.articles, hasLength(8));
      expect(deck.initialIndex, 1);
    });
  });
}
