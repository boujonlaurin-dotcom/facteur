import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/services/read_sync_service.dart';
import 'package:facteur/features/flux_continu/widgets/daily_completion_recap.dart';
import 'package:facteur/features/sources/models/source_model.dart';

/// Epic 30 — « lu jusqu'au bout ».
///
/// Le point à protéger : `readingProgress` est plafonné à 25 pour ~90 % du
/// catalogue (contenu partiel), donc aucun seuil de progression ne peut servir
/// de critère de complétion. Le libellé doit venir de `completedAt`.
void main() {
  final source = Source(
    id: 's1',
    name: 'Le Monde',
    url: 'https://lemonde.fr',
    type: SourceType.article,
  );

  Content content({
    ContentType contentType = ContentType.article,
    ContentStatus status = ContentStatus.unseen,
    int readingProgress = 0,
    DateTime? completedAt,
  }) {
    return Content(
      id: 'c1',
      title: 'T',
      url: 'https://lemonde.fr/a',
      contentType: contentType,
      publishedAt: DateTime(2026, 7, 24),
      source: source,
      status: status,
      readingProgress: readingProgress,
      completedAt: completedAt,
    );
  }

  group('Content.isCompleted', () {
    test('vient de completedAt, pas de la progression', () {
      expect(content(readingProgress: 100).isCompleted, isFalse);
      expect(
        content(completedAt: DateTime(2026, 7, 24, 9)).isCompleted,
        isTrue,
      );
    });

    test(
      'un article partiel plafonné à 25 est bien « Lu jusqu\'au bout »',
      () {
        // Le cas nominal : sans completedAt, ces lectures étaient étiquetées
        // « Parcouru » — on démotivait le comportement qu'on veut encourager.
        final c = content(
          readingProgress: 25,
          status: ContentStatus.consumed,
          completedAt: DateTime(2026, 7, 24, 9),
        );
        expect(c.readingLabel, 'Lu jusqu\'au bout');
      },
    );

    test('« Parcouru » a disparu — deux états seulement', () {
      expect(
        content(readingProgress: 5, status: ContentStatus.seen).readingLabel,
        'Lu',
      );
    });

    test('un article jamais ouvert n\'a aucun libellé', () {
      expect(content().readingLabel, isNull);
    });
  });

  group('Content.fromJson', () {
    test('parse completed_at', () {
      final json = <String, dynamic>{
        'id': 'c1',
        'title': 'T',
        'url': 'https://x',
        'content_type': 'article',
        'published_at': '2026-07-24T08:00:00Z',
        'source': {
          'id': 's1',
          'name': 'S',
          'url': 'https://s',
          'type': 'article',
        },
        'completed_at': '2026-07-24T09:30:00Z',
      };
      expect(Content.fromJson(json).completedAt, isNotNull);
      expect(Content.fromJson(json).isCompleted, isTrue);
    });

    test('completed_at absent ⇒ null, et non « non terminé »', () {
      final json = <String, dynamic>{
        'id': 'c1',
        'title': 'T',
        'url': 'https://x',
        'content_type': 'article',
        'published_at': '2026-07-24T08:00:00Z',
        'source': {
          'id': 's1',
          'name': 'S',
          'url': 'https://s',
          'type': 'article',
        },
      };
      expect(Content.fromJson(json).completedAt, isNull);
    });
  });

  group('CompletionSource', () {
    test('round-trip via la valeur réseau', () {
      for (final s in CompletionSource.values) {
        expect(CompletionSource.fromWire(s.wireValue), s);
      }
    });

    test('valeur inconnue ⇒ in_app, jamais une exception', () {
      expect(CompletionSource.fromWire('martian'), CompletionSource.inApp);
      expect(CompletionSource.fromWire(null), CompletionSource.inApp);
    });
  });

  group('PendingCompletionQueue (préfixe done:)', () {
    late Box<String> box;

    setUp(() async {
      Hive.init('./.dart_tool/hive_test_completion');
      box = await Hive.openBox<String>(PendingReadQueue.boxName);
      await box.clear();
    });

    tearDown(() async => box.deleteFromDisk());

    test('les deux files cohabitent dans la même box sans se voir', () async {
      final reads = PendingReadQueue(box);
      final completions = PendingReadQueue(
        box,
        keyPrefix: PendingReadQueue.completionPrefix,
      );

      await reads.enqueue('u1', 'c1');
      await completions.enqueue('u1', 'c2', extra: {'source': 'web'});

      expect(reads.pendingForUser('u1').values, ['c1']);
      expect(completions.pendingForUser('u1').values, ['c2']);
    });

    test('payloadFor restitue la source de complétion', () async {
      final completions = PendingReadQueue(
        box,
        keyPrefix: PendingReadQueue.completionPrefix,
      );
      await completions.enqueue('u1', 'c1', extra: {'source': 'web'});

      expect(completions.payloadFor('u1', 'c1')?['source'], 'web');
      expect(completions.payloadFor('u1', 'absent'), isNull);
    });

    test('clearForUser ne touche que son propre préfixe', () async {
      final reads = PendingReadQueue(box);
      final completions = PendingReadQueue(
        box,
        keyPrefix: PendingReadQueue.completionPrefix,
      );
      await reads.enqueue('u1', 'c1');
      await completions.enqueue('u1', 'c1');

      await completions.clearForUser('u1');

      expect(reads.pendingForUser('u1'), isNotEmpty);
      expect(completions.pendingForUser('u1'), isEmpty);
    });
  });

  group('Taglines du bloc de clôture', () {
    test('stables pour un même jour, et déterministes', () {
      final day = DateTime.utc(2026, 7, 24, 10);
      expect(pickCompletionTagline(day), pickCompletionTagline(day));
    });

    test('la référence produit fait partie du jeu', () {
      expect(
        kCompletionTaglines,
        contains('Moins d’info, plus de compréhension.'),
      );
    });

    test('aucune formulation comparative ni point d\'exclamation', () {
      // Le survol est le comportement de la grande majorité des ouvertures :
      // une phrase comparative ferait honte à l'utilisateur médian.
      for (final t in kCompletionTaglines) {
        expect(t, isNot(contains('!')));
        expect(t.toLowerCase(), isNot(contains('mieux que vingt')));
      }
    });

    test('toutes les taglines sont atteignables sur un cycle de jours', () {
      final seen = <String>{};
      for (var i = 0; i < 400; i++) {
        seen.add(pickCompletionTagline(DateTime.utc(2026, 1, 1).add(Duration(days: i))));
      }
      expect(seen.length, kCompletionTaglines.length);
    });
  });
}
