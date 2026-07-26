import 'package:facteur/features/feed/utils/search_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('foldForSearch', () {
    test('replie casse et accents FR', () {
      expect(foldForSearch('Écologie'), 'ecologie');
      expect(foldForSearch('L\'Équipe'), 'l\'equipe');
      expect(foldForSearch('Ça Ïrait'), 'ca irait');
    });

    test('préserve la longueur (offsets de surlignage restent valides)', () {
      const input = 'Émission spéciale — Élysée';
      expect(foldForSearch(input).length, input.length);
    });
  });

  group('matchQuality', () {
    test('exact ignore casse et accents', () {
      expect(matchQuality('mediapart', 'Mediapart'), MatchQuality.exact);
      expect(matchQuality('ECOLOGIE', 'Écologie'), MatchQuality.exact);
    });

    test('prefix quand le libellé commence par la requête', () {
      expect(matchQuality('media', 'Mediapart'), MatchQuality.prefix);
    });

    test('wordPrefix quand un mot interne commence par la requête', () {
      expect(matchQuality('monde', 'Le Monde'), MatchQuality.wordPrefix);
      expect(matchQuality('info', 'France-Info'), MatchQuality.wordPrefix);
    });

    test('sous-chaîne en milieu de mot est rejetée (plus de tier contains)', () {
      // Le tier `contains` a été retiré : « belle » ne doit plus remonter
      // « Isabelle » ni « poubelle » (sous-chaîne au milieu d'un mot).
      expect(matchQuality('belle', 'Isabelle'), MatchQuality.none);
      expect(matchQuality('belle', 'poubelle'), MatchQuality.none);
      expect(matchQuality('iapa', 'Mediapart'), MatchQuality.none);
      // La frontière de mot, elle, reste acceptée.
      expect(matchQuality('belle', 'La belle époque'), MatchQuality.wordPrefix);
      expect(matchQuality('belle', 'belles idées'), MatchQuality.prefix);
    });

    test('une requête multi-mots matche aussi sur frontière de mot', () {
      // Le découpage en mots ne saurait jamais reconnaître une requête qui
      // contient elle-même un séparateur : « monde diplo » tombait en
      // `contains`, à égalité avec un match au milieu d'un mot.
      expect(
        matchQuality('monde diplo', 'Le Monde Diplomatique'),
        MatchQuality.wordPrefix,
      );
      expect(
        matchQuality('lemonde.fr', 'https://lemonde.fr'),
        MatchQuality.wordPrefix,
      );
    });

    test('requête vide ou blanche ne matche jamais', () {
      expect(matchQuality('', 'Mediapart'), MatchQuality.none);
      expect(matchQuality('   ', 'Mediapart'), MatchQuality.none);
    });

    test('none quand rien ne correspond', () {
      expect(matchQuality('zzz', 'Mediapart'), MatchQuality.none);
    });
  });

  group('matchQuality — fuzzy (fautes de frappe)', () {
    test('faute simple sur un mot long (≥7) → fuzzy', () {
      expect(matchQuality('libertaion', 'Libération'), MatchQuality.fuzzy);
    });

    test('mot collé rattrapé mot à mot du candidat → fuzzy', () {
      // « lemonde » (7) est à distance 2 du mot « monde » de « Le Monde ».
      expect(matchQuality('lemonde', 'Le Monde'), MatchQuality.fuzzy);
    });

    test('seuil 1 pour 4-6 caractères : 1 faute OK, 2+ non', () {
      expect(matchQuality('mande', 'Le Monde'), MatchQuality.fuzzy); // 1 faute
      expect(matchQuality('xxxde', 'Le Monde'), MatchQuality.none); // 3 fautes
    });

    test('pas de fuzzy sous 4 caractères', () {
      // Une distance de 1 sur une requête courte rendrait presque tout
      // équivalent : le fuzzy est désactivé sous 4 caractères.
      expect(matchQuality('abc', 'abd'), MatchQuality.none);
    });
  });

  group('rankMatches', () {
    const candidates = [
      'Le Monde Diplomatique',
      'Le Monde',
      'Mediapart',
      'Courrier International',
    ];

    List<String> labelsFor(String query) => rankMatches<String>(
          query,
          candidates,
          label: (s) => s,
        ).map((m) => m.item).toList();

    test('requête vide → aucun résultat', () {
      expect(labelsFor(''), isEmpty);
    });

    test('meilleure qualité en tête, puis libellé le plus court', () {
      expect(labelsFor('le monde'), ['Le Monde', 'Le Monde Diplomatique']);
    });

    test('prefix passe devant wordPrefix', () {
      final ranked = rankMatches<String>(
        'monde',
        candidates,
        label: (s) => s,
      );
      expect(ranked.first.item, 'Le Monde');
      expect(ranked.first.quality, MatchQuality.wordPrefix);
    });

    test('les alias participent au matching', () {
      final ranked = rankMatches<String>(
        'lemonde.fr',
        ['Le Monde'],
        label: (s) => s,
        aliases: (_) => ['https://lemonde.fr'],
      );
      expect(ranked, hasLength(1));
      expect(ranked.first.quality, MatchQuality.wordPrefix);
    });

    test('un alias exact prime sur un label partiel', () {
      final ranked = rankMatches<String>(
        'mediapart',
        ['Médiapart — abonnés'],
        label: (s) => s,
        aliases: (_) => ['Mediapart'],
      );
      expect(ranked.first.quality, MatchQuality.exact);
    });

    test('tri déterministe à qualité et longueur égales', () {
      final first = rankMatches<String>('a', const ['ab', 'aa'], label: (s) => s);
      final second =
          rankMatches<String>('a', const ['aa', 'ab'], label: (s) => s);
      expect(first.map((m) => m.item), second.map((m) => m.item));
      expect(first.map((m) => m.item), ['aa', 'ab']);
    });
  });

  group('looksLikeSourceQuery', () {
    test('vrai pour une URL ou un domaine', () {
      expect(looksLikeSourceQuery('https://lemonde.fr'), isTrue);
      expect(looksLikeSourceQuery('www.mediapart.fr'), isTrue);
      expect(looksLikeSourceQuery('lemonde.fr'), isTrue);
      expect(looksLikeSourceQuery('blog.example.co.uk'), isTrue);
    });

    test('faux pour une requête en langage naturel', () {
      expect(looksLikeSourceQuery('élection présidentielle'), isFalse);
      expect(looksLikeSourceQuery('écologie'), isFalse);
      // Une phrase contenant un point reste une phrase.
      expect(looksLikeSourceQuery('fin de partie. suite'), isFalse);
      expect(looksLikeSourceQuery(''), isFalse);
    });
  });
}
