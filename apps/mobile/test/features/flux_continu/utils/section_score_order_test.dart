import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/utils/section_score_order.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// Article porteur (ou non) d'un `score_total`. Seul le score compte ici : le
/// reste du `Content` est du remplissage minimal.
Content _article(double? score, {String id = 'a'}) => Content(
  id: id,
  title: 'Titre $id',
  url: 'https://example.test/$id',
  contentType: ContentType.article,
  publishedAt: DateTime(2026, 1, 1),
  source: Source(id: 's', name: 'S', type: SourceType.article),
  recommendationReason: score == null
      ? null
      : RecommendationReason(label: 'Recommandé', scoreTotal: score),
);

List<Content> _block(List<double?> scores) => [
  for (var i = 0; i < scores.length; i++) _article(scores[i], id: 'a$i'),
];

void main() {
  group('blockScore', () {
    test('somme les 3 meilleurs scores, pas les 3 premiers affichés', () {
      // Ordre d'affichage volontairement croissant : si l'implémentation prenait
      // les 3 premiers, elle renverrait 1+2+3 = 6. Les 3 meilleurs : 90+80+3.
      expect(blockScore(_block([1, 2, 3, 90, 80])), 173);
    });

    test('les slots manquants comptent 0 — un bloc à 1 article est pénalisé',
        () {
      expect(blockScore(_block([100])), 100);
      expect(blockScore(_block([100, 100, 100])), 300);
    });

    test('chaque terme est clampé à 0 (une pénalité ne retranche pas)', () {
      // Sans clamp : 100 + 50 + (-40) = 110.
      expect(blockScore(_block([100, 50, -40])), 150);
      expect(blockScore(_block([-10, -20])), 0);
    });

    test('les articles sans recommendationReason ne contribuent pas', () {
      expect(blockScore(_block([100, null, 50])), 150);
      expect(blockScore(_block([null, null])), 0);
      expect(blockScore(const []), 0);
    });

    test('topN est paramétrable', () {
      expect(blockScore(_block([10, 20, 30, 40]), topN: 2), 70);
    });
  });

  group('rankKeysByBlockScore', () {
    test('trie par score décroissant', () {
      final ranked = rankKeysByBlockScore(
        {'a': 10.0, 'b': 300.0, 'c': 120.0},
      );
      expect(ranked, ['b', 'c', 'a']);
    });

    test(
        'tri stable : à score égal, l\'ordre d\'insertion de la map '
        '(= ordre d\'affichage) départage', () {
      final ranked = rankKeysByBlockScore(
        {'a': 50.0, 'b': 50.0, 'c': 50.0},
      );
      expect(ranked, ['a', 'b', 'c']);
    });

    test('bloc à 1 article vs bloc à 3 articles, meilleur score égal', () {
      final maigre = blockScore(_block([90]));
      final riche = blockScore(_block([90, 60, 40]));
      final ranked = rankKeysByBlockScore(
        {'theme:maigre': maigre, 'theme:riche': riche},
      );
      expect(ranked, ['theme:riche', 'theme:maigre']);
    });

    test('une map vide ne donne aucun classement', () {
      expect(rankKeysByBlockScore(const {}), isEmpty);
    });
  });

  group('applyScoreOrder', () {
    test('replace les clés scorées dans l\'ordre du classement', () {
      expect(
        applyScoreOrder(
          ['theme:a', 'theme:b', 'theme:c'],
          ['theme:c', 'theme:a', 'theme:b'],
        ),
        ['theme:c', 'theme:a', 'theme:b'],
      );
    });

    test('une clé non scorée garde sa position absolue, y compris entre deux '
        'clés triées', () {
      expect(
        applyScoreOrder(
          ['theme:a', 'essentiel', 'theme:b'],
          ['theme:b', 'theme:a'],
        ),
        // `essentiel` n'est pas dans le classement : il reste en position 1.
        ['theme:b', 'essentiel', 'theme:a'],
      );
    });

    test('les clés éditoriales de tête et de queue ne coulent pas', () {
      expect(
        applyScoreOrder(
          ['essentiel', 'theme:a', 'theme:b', 'bonnes'],
          ['theme:b', 'theme:a'],
        ),
        ['essentiel', 'theme:b', 'theme:a', 'bonnes'],
      );
    });

    test('une clé obsolète du classement est ignorée, pas rajoutée en queue',
        () {
      expect(
        applyScoreOrder(
          ['theme:a', 'theme:b'],
          ['theme:disparu', 'theme:b', 'theme:a'],
        ),
        ['theme:b', 'theme:a'],
      );
    });

    test('classement vide ou sans intersection → no-op', () {
      expect(applyScoreOrder(['a', 'b'], const []), ['a', 'b']);
      expect(applyScoreOrder(['a', 'b'], ['x', 'y']), ['a', 'b']);
      expect(applyScoreOrder(const [], ['a']), isEmpty);
    });
  });
}
