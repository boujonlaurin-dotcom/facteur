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
    DateTime? completedAt,
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
      completedAt: completedAt,
    );
  }

  final completedStamp = DateTime(2026, 7, 24, 9);

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

    test('returns "Vu jusqu\'au bout" once completed', () {
      final c = makeContent(
        readingProgress: 90,
        status: ContentStatus.seen,
        completedAt: completedStamp,
      );
      expect(c.readingLabel, 'Vu jusqu\'au bout');
    });

    test('stays "Vu en partie" at 100% progress without a completion stamp', () {
      // Epic 30 : la progression seule ne prouve plus rien — elle est plafonnée
      // à 25 pour ~90 % du catalogue.
      final c = makeContent(readingProgress: 100, status: ContentStatus.seen);
      expect(c.readingLabel, 'Vu en partie');
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
        completedAt: completedStamp,
      );
      expect(c.readingLabel, 'Vu jusqu\'au bout');
    });
  });

  // -----------------------------------------------------------------------
  // 3. readingLabel for article types — Epic 30 : deux états seulement,
  //    adossés à `completedAt` et non plus au seuil de progression.
  // -----------------------------------------------------------------------

  group('Content.readingLabel for article', () {
    test('returns "Lu jusqu\'au bout" once completed', () {
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 95,
        status: ContentStatus.seen,
        source: mockArticleSource,
        completedAt: completedStamp,
      );
      expect(c.readingLabel, 'Lu jusqu\'au bout');
    });

    test('a completed partial article is not downgraded by its capped progress',
        () {
      // Le cas nominal : ~90 % du catalogue plafonne à 25, et affichait donc
      // « Parcouru » sur une lecture pourtant menée à son terme.
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 25,
        status: ContentStatus.consumed,
        source: mockArticleSource,
        completedAt: completedStamp,
      );
      expect(c.readingLabel, 'Lu jusqu\'au bout');
    });

    test('returns "Lu" at mid progress without a completion stamp', () {
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 50,
        status: ContentStatus.seen,
        source: mockArticleSource,
      );
      expect(c.readingLabel, 'Lu');
    });

    test('returns "Lu" at low progress — « Parcouru » a été retiré', () {
      final c = makeContent(
        contentType: ContentType.article,
        readingProgress: 15,
        status: ContentStatus.seen,
        source: mockArticleSource,
      );
      expect(c.readingLabel, 'Lu');
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
