import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Shared mock source for all tests
  final mockSource = Source(
    id: '1',
    name: 'Test Channel',
    url: 'https://youtube.com/@test',
    type: SourceType.youtube,
    theme: 'TECH',
  );

  final mockArticleSource = Source(
    id: '2',
    name: 'TechCrunch',
    url: 'https://techcrunch.com',
    type: SourceType.article,
    theme: 'TECH',
  );

  Content makeContent({
    ContentType contentType = ContentType.youtube,
    ContentStatus status = ContentStatus.unseen,
    int readingProgress = 0,
    Source? source,
  }) {
    return Content(
      id: '123',
      title: 'Test Content',
      url: 'https://youtube.com/watch?v=abc',
      contentType: contentType,
      publishedAt: DateTime(2024, 6, 15),
      source: source ?? mockSource,
      status: status,
      readingProgress: readingProgress,
    );
  }

  // -----------------------------------------------------------------------
  // 1. isVideo getter
  // -----------------------------------------------------------------------

  group('Content.isVideo', () {
    test('returns true for ContentType.youtube', () {
      final c = makeContent(contentType: ContentType.youtube);
      expect(c.isVideo, isTrue);
    });

    test('returns true for ContentType.video', () {
      final c = makeContent(contentType: ContentType.video);
      expect(c.isVideo, isTrue);
    });

    test('returns false for ContentType.article', () {
      final c = makeContent(contentType: ContentType.article);
      expect(c.isVideo, isFalse);
    });

    test('returns false for ContentType.audio', () {
      final c = makeContent(contentType: ContentType.audio);
      expect(c.isVideo, isFalse);
    });
  });

  // -----------------------------------------------------------------------
  // 2. readingLabel for video types
  // -----------------------------------------------------------------------

  group('Content.readingLabel for video', () {
    test('returns null when unseen with 0 progress', () {
      final c = makeContent(readingProgress: 0);
      expect(c.readingLabel, isNull);
    });

    test('returns "Vu jusqu\'au bout" at 90% progress', () {
      final c = makeContent(readingProgress: 90, status: ContentStatus.seen);
      expect(c.readingLabel, 'Vu jusqu\'au bout');
    });

    test('returns "Vu jusqu\'au bout" at 100% progress', () {
      final c = makeContent(readingProgress: 100, status: ContentStatus.seen);
      expect(c.readingLabel, 'Vu jusqu\'au bout');
    });

    test('returns "Vu en partie" at 50% progress', () {
      final c = makeContent(readingProgress: 50, status: ContentStatus.seen);
      expect(c.readingLabel, 'Vu en partie');
    });

    test('returns "Vu en partie" at 25% progress', () {
      final c = makeContent(readingProgress: 25, status: ContentStatus.seen);
      expect(c.readingLabel, 'Vu en partie');
    });

    test('returns null below 25% progress when seen', () {
      final c = makeContent(readingProgress: 10, status: ContentStatus.seen);
      expect(c.readingLabel, isNull);
    });

    test('returns "Vu en partie" when consumed via timer but no progress', () {
      final c = makeContent(
        readingProgress: 0,
        status: ContentStatus.consumed,
      );
      expect(c.readingLabel, 'Vu en partie');
    });

    test('works the same for ContentType.video', () {
      final c = makeContent(
        contentType: ContentType.video,
        readingProgress: 95,
        status: ContentStatus.seen,
      );
      expect(c.readingLabel, 'Vu jusqu\'au bout');
    });
  });

  // -----------------------------------------------------------------------
  // 3. readingLabel for article types (unchanged)
  // -----------------------------------------------------------------------

  group('Content.readingLabel for article', () {
    test('returns "Lu jusqu\'au bout" at 90%+ progress', () {
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 95,
        status: ContentStatus.seen,
        source: mockArticleSource,
      );
      expect(c.readingLabel, 'Lu jusqu\'au bout');
    });

    test('returns "Lu" at 30-89% progress', () {
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 50,
        status: ContentStatus.seen,
        source: mockArticleSource,
      );
      expect(c.readingLabel, 'Lu');
    });

    test('returns "Parcouru" at low progress (1-29%)', () {
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 15,
        status: ContentStatus.seen,
        source: mockArticleSource,
      );
      expect(c.readingLabel, 'Parcouru');
    });

    test('returns "Lu" when consumed via timer with 0 scroll', () {
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 0,
        status: ContentStatus.consumed,
        source: mockArticleSource,
      );
      expect(c.readingLabel, 'Lu');
    });
  });
}
