import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/flux_continu/providers/essentiel_triage_provider.dart';
import 'package:facteur/features/flux_continu/utils/essentiel_deck.dart';
import 'package:facteur/features/sources/models/source_model.dart';

EssentielArticle _article(String id, {int rank = 1}) => EssentielArticle(
      contentId: id,
      title: 'title-$id',
      url: 'https://x.test/$id',
      publishedAt: DateTime(2026, 1, 1),
      sourceName: 'S',
      sourceLetter: 'S',
      sectionLabel: 'Politique',
      rank: rank,
    );

Content _content(String id) => Content(
      id: id,
      title: 'carousel-$id',
      url: 'https://x.test/$id',
      contentType: ContentType.article,
      publishedAt: DateTime(2026, 1, 1),
      source: Source(id: 's', name: 'S', type: SourceType.article),
    );

FeedCarouselData _carousel(List<Content> items) => FeedCarouselData(
      carouselType: 'essentiel_extra',
      title: 'Aussi ce matin',
      emoji: '',
      position: 0,
      items: items,
      badges: const [],
    );

EssentielSection _section({
  int articles = 5,
  FeedCarouselData? carousel,
}) =>
    EssentielSection(
      articles: List.generate(
        articles,
        (i) => _article('e$i', rank: i + 1),
      ),
      carousel: carousel,
    );

/// Tri terminé (arrêt volontaire) sur [slate], avec les décisions données.
EssentielTriageState _triage({
  required List<String> slate,
  required Map<String, TriageDecision> decisions,
  bool stopped = true,
  bool hydrated = true,
}) =>
    EssentielTriageState(
      dayKey: 'test',
      slate: slate,
      decisions: {
        for (var i = 0; i < slate.length; i++)
          if (decisions[slate[i]] != null)
            slate[i]: TriageEntry(
              contentId: slate[i],
              decision: decisions[slate[i]]!,
              rank: i + 1,
              via: TriageVia.swipe,
            ),
      },
      stopped: stopped,
      hydrated: hydrated,
    );

void main() {
  group('essentielTriagePool', () {
    test('slate, puis carrousel inédit, puis rapatriés — dédupés', () {
      final pool = essentielTriagePool(
        articles: [_article('e0'), _article('e1')],
        // `e1` est déjà dans le slate : il ne doit pas entrer deux fois.
        carousel: _carousel([_content('e1'), _content('k0')]),
        fetched: [_article('f0'), _article('k0')],
      );

      expect(pool.map((a) => a.contentId), ['e0', 'e1', 'k0', 'f0']);
    });
  });

  group('essentielArticleDeck — tri en cours', () {
    test('aucune navigation tant que le tri n’est pas terminé', () {
      final section = _section();
      // Deux articles décidés sur cinq, objectif par défaut non atteint : la
      // pile est encore active.
      final triage = _triage(
        slate: const ['e0', 'e1', 'e2', 'e3', 'e4'],
        decisions: const {
          'e0': TriageDecision.keep,
          'e1': TriageDecision.pass,
        },
        stopped: false,
      );

      expect(triage.done, isFalse);
      expect(
        essentielArticleDeck(
          section: section,
          triage: triage,
          tappedContentId: 'e2',
          isToday: true,
        ),
        isNull,
      );
    });

    test('une ligne déjà gardée n’ouvre pas de deck non plus', () {
      final triage = _triage(
        slate: const ['e0', 'e1', 'e2', 'e3', 'e4'],
        decisions: const {
          'e0': TriageDecision.keep,
          'e1': TriageDecision.keep,
        },
        stopped: false,
      );

      expect(
        essentielArticleDeck(
          section: _section(),
          triage: triage,
          // `e0` est visible sous la pile, dans la liste des gardés en cours.
          tappedContentId: 'e0',
          isToday: true,
        ),
        isNull,
      );
    });

    test('tri indéterminé (slate pas encore gelé) → pas de deck', () {
      expect(
        essentielArticleDeck(
          section: _section(),
          triage: const EssentielTriageState(dayKey: 'test'),
          tappedContentId: 'e0',
          isToday: true,
        ),
        isNull,
      );
    });
  });

  group('essentielArticleDeck — tri terminé', () {
    test('le deck est la liste des gardés, dans l’ordre du slate', () {
      final deck = essentielArticleDeck(
        section: _section(),
        triage: _triage(
          slate: const ['e0', 'e1', 'e2', 'e3', 'e4'],
          decisions: const {
            'e0': TriageDecision.keep,
            'e1': TriageDecision.pass,
            'e2': TriageDecision.later,
            'e3': TriageDecision.pass,
            'e4': TriageDecision.keep,
          },
        ),
        tappedContentId: 'e2',
        isToday: true,
      );

      // Les rejetés (`e1`, `e3`) ne sont pas atteignables au swipe : y revenir
      // serait annuler la décision qu’on vient de prendre. `later` est un choix
      // positif, il reste dans la séquence.
      expect(deck!.articles.map((a) => a.id), ['e0', 'e2', 'e4']);
      expect(deck.initialIndex, 1);
      expect(deck.isNavigable, isTrue);
      expect(deck.sectionKey, 'essentiel_v3');
    });

    test('un gardé venu du carrousel entre dans le deck', () {
      final deck = essentielArticleDeck(
        section: _section(
          articles: 2,
          carousel: _carousel([_content('k0')]),
        ),
        triage: _triage(
          slate: const ['e0', 'e1', 'k0'],
          decisions: const {
            'e0': TriageDecision.keep,
            'e1': TriageDecision.pass,
            'k0': TriageDecision.keep,
          },
        ),
        tappedContentId: 'k0',
        isToday: true,
      );

      expect(deck!.articles.map((a) => a.id), ['e0', 'k0']);
      expect(deck.initialIndex, 1);
    });

    test('un gardé rapatrié au réseau entre dans le deck', () {
      final deck = essentielArticleDeck(
        section: _section(articles: 2),
        triage: _triage(
          slate: const ['e0', 'e1', 'f0'],
          decisions: const {
            'e0': TriageDecision.keep,
            'e1': TriageDecision.keep,
            'f0': TriageDecision.keep,
          },
        ),
        tappedContentId: 'f0',
        isToday: true,
        fetched: [_article('f0')],
      );

      expect(deck!.articles.map((a) => a.id), ['e0', 'e1', 'f0']);
      expect(deck.initialIndex, 2);
    });

    test('un seul gardé → rien à enchaîner, pas de deck', () {
      expect(
        essentielArticleDeck(
          section: _section(),
          triage: _triage(
            slate: const ['e0', 'e1'],
            decisions: const {
              'e0': TriageDecision.keep,
              'e1': TriageDecision.pass,
            },
          ),
          tappedContentId: 'e0',
          isToday: true,
        ),
        isNull,
      );
    });

    test('article tapé hors des gardés → pas de deck', () {
      expect(
        essentielArticleDeck(
          section: _section(),
          triage: _triage(
            slate: const ['e0', 'e1', 'e2'],
            decisions: const {
              'e0': TriageDecision.keep,
              'e1': TriageDecision.keep,
              'e2': TriageDecision.pass,
            },
          ),
          tappedContentId: 'e2',
          isToday: true,
        ),
        isNull,
      );
    });

    test('un gardé introuvable dans le pool est ignoré, pas fatal', () {
      final deck = essentielArticleDeck(
        section: _section(articles: 2),
        triage: _triage(
          slate: const ['e0', 'zz', 'e1'],
          decisions: const {
            'e0': TriageDecision.keep,
            'zz': TriageDecision.keep,
            'e1': TriageDecision.keep,
          },
        ),
        tappedContentId: 'e1',
        isToday: true,
      );

      expect(deck!.articles.map((a) => a.id), ['e0', 'e1']);
      expect(deck.initialIndex, 1);
    });
  });

  group('essentielArticleDeck — lettre passée', () {
    test('non-régression : le deck reste la lettre entière', () {
      // Une lettre passée est figée : elle n’a pas été triée, et le tri du jour
      // (ici terminé sur d’autres ids) ne la concerne pas.
      final deck = essentielArticleDeck(
        section: _section(),
        triage: _triage(
          slate: const ['x0', 'x1'],
          decisions: const {
            'x0': TriageDecision.keep,
            'x1': TriageDecision.pass,
          },
        ),
        tappedContentId: 'e3',
        isToday: false,
      );

      expect(deck!.articles.map((a) => a.id), ['e0', 'e1', 'e2', 'e3', 'e4']);
      expect(deck.initialIndex, 3);
    });
  });
}
