import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';

/// Story 30.4 — spectre d'engagement « Non lu / Ouvert / Lu en partie / Lu
/// jusqu'au bout ». Fichier volontairement sans dépendance widget/écran : la
/// logique de dérivation est du pur modèle et doit rester compilable/testable
/// indépendamment du reste de l'app.
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
    int? timeSpentSeconds,
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
      timeSpentSeconds: timeSpentSeconds,
      completedAt: completedAt,
    );
  }

  group('Content.readState', () {
    test('jamais ouvert → unread', () {
      expect(content().readState, ReadState.unread);
      expect(content().readingLabel, isNull);
    });

    test('consommé + temps < 5s → opened', () {
      final c = content(status: ContentStatus.consumed, timeSpentSeconds: 2);
      expect(c.readState, ReadState.opened);
      expect(c.readingLabel, 'Ouvert');
    });

    test('consommé + temps ≥ 5s → partiallyRead', () {
      final c = content(status: ContentStatus.consumed, timeSpentSeconds: 12);
      expect(c.readState, ReadState.partiallyRead);
      expect(c.readingLabel, 'Lu en partie');
    });

    test('temps inconnu (null) → partiallyRead, jamais opened', () {
      expect(content(status: ContentStatus.consumed).readState,
          ReadState.partiallyRead);
    });

    test('vidéo progress ≥ 25 → partiallyRead même sans temps', () {
      final c = content(
        contentType: ContentType.youtube,
        status: ContentStatus.consumed,
        readingProgress: 25,
      );
      expect(c.readState, ReadState.partiallyRead);
      expect(c.readingLabel, 'Vu en partie');
    });

    test('vidéo ouverte < 5s → opened', () {
      final c = content(
        contentType: ContentType.youtube,
        status: ContentStatus.consumed,
        timeSpentSeconds: 1,
      );
      expect(c.readState, ReadState.opened);
    });

    test('completé prime sur tout → completed', () {
      final c = content(
        status: ContentStatus.consumed,
        timeSpentSeconds: 1,
        completedAt: DateTime(2026, 7, 24, 9),
      );
      expect(c.readState, ReadState.completed);
    });
  });

  group('opacityForReadState — plus on s\'engage, plus la carte s\'efface', () {
    test('barème', () {
      expect(opacityForReadState(ReadState.unread), 1.0);
      expect(opacityForReadState(ReadState.opened), 0.8);
      expect(opacityForReadState(ReadState.partiallyRead), 0.6);
      expect(opacityForReadState(ReadState.completed), 0.6);
    });
  });

  group('effectiveReadState — fusion session', () {
    test('consommé cette session → opened minimum (jamais unread)', () {
      expect(
        effectiveReadState(ReadState.unread,
            consumedThisSession: true, completedThisSession: false),
        ReadState.opened,
      );
    });

    test('complété cette session prime', () {
      expect(
        effectiveReadState(ReadState.opened,
            consumedThisSession: true, completedThisSession: true),
        ReadState.completed,
      );
    });

    test('n\'écrase pas un état serveur déjà plus engagé', () {
      expect(
        effectiveReadState(ReadState.partiallyRead,
            consumedThisSession: true, completedThisSession: false),
        ReadState.partiallyRead,
      );
    });
  });

  group('Content.fromJson — time_spent_seconds', () {
    final base = <String, dynamic>{
      'id': 'c1',
      'title': 'T',
      'url': 'https://x',
      'content_type': 'article',
      'published_at': '2026-07-24T08:00:00Z',
      'source': {'id': 's1', 'name': 'S', 'url': 'https://s', 'type': 'article'},
    };

    test('absent → null', () {
      expect(Content.fromJson(base).timeSpentSeconds, isNull);
    });

    test('présent → int', () {
      expect(
        Content.fromJson({...base, 'time_spent_seconds': 3}).timeSpentSeconds,
        3,
      );
    });
  });
}
