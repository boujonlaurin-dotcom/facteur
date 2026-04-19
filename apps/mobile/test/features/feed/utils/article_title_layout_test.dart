import 'package:facteur/features/feed/utils/article_title_layout.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ArticleTitleLayout.titleMaxLines', () {
    test('returns 3 with image', () {
      expect(ArticleTitleLayout.titleMaxLines(hasImage: true), 3);
    });
    test('returns 5 without image', () {
      expect(ArticleTitleLayout.titleMaxLines(hasImage: false), 5);
    });
  });

  group('ArticleTitleLayout.estimateTitleLines', () {
    test('empty title returns 1', () {
      final lines = ArticleTitleLayout.estimateTitleLines(
        title: '',
        availableWidth: 300,
        hasImage: false,
      );
      expect(lines, 1);
    });

    test('whitespace-only title returns 1', () {
      final lines = ArticleTitleLayout.estimateTitleLines(
        title: '   ',
        availableWidth: 300,
        hasImage: false,
      );
      expect(lines, 1);
    });

    test('short title fits in 1 line', () {
      final lines = ArticleTitleLayout.estimateTitleLines(
        title: 'Short title',
        availableWidth: 300,
        hasImage: false,
      );
      expect(lines, 1);
    });

    test('long title clamps to 3 lines when image is present', () {
      final lines = ArticleTitleLayout.estimateTitleLines(
        title: 'x' * 500,
        availableWidth: 300,
        hasImage: true,
      );
      expect(lines, 3);
    });

    test('long title clamps to 5 lines when image is absent', () {
      final lines = ArticleTitleLayout.estimateTitleLines(
        title: 'x' * 500,
        availableWidth: 300,
        hasImage: false,
      );
      expect(lines, 5);
    });
  });

  group('ArticleTitleLayout.descriptionMaxLines (feed)', () {
    test('hidden when image is present', () {
      expect(
        ArticleTitleLayout.descriptionMaxLines(
          estimatedTitleLines: 2,
          hasImage: true,
          hasDescription: true,
        ),
        0,
      );
    });

    test('hidden when description is empty', () {
      expect(
        ArticleTitleLayout.descriptionMaxLines(
          estimatedTitleLines: 2,
          hasImage: false,
          hasDescription: false,
        ),
        0,
      );
    });

    test('title <=3 lines -> 2 desc lines', () {
      for (final t in [1, 2, 3]) {
        expect(
          ArticleTitleLayout.descriptionMaxLines(
            estimatedTitleLines: t,
            hasImage: false,
            hasDescription: true,
          ),
          2,
        );
      }
    });

    test('title 4 lines -> 1 desc line', () {
      expect(
        ArticleTitleLayout.descriptionMaxLines(
          estimatedTitleLines: 4,
          hasImage: false,
          hasDescription: true,
        ),
        1,
      );
    });

    test('title 5 lines -> 0 desc line', () {
      expect(
        ArticleTitleLayout.descriptionMaxLines(
          estimatedTitleLines: 5,
          hasImage: false,
          hasDescription: true,
        ),
        0,
      );
    });
  });

  group('ArticleTitleLayout.descriptionMaxLinesForCarousel', () {
    test('hidden when image is present', () {
      expect(
        ArticleTitleLayout.descriptionMaxLinesForCarousel(
          estimatedTitleLines: 2,
          hasImage: true,
          hasDescription: true,
        ),
        0,
      );
    });

    test('title <=3 lines -> 4 desc lines (current carousel default)', () {
      expect(
        ArticleTitleLayout.descriptionMaxLinesForCarousel(
          estimatedTitleLines: 3,
          hasImage: false,
          hasDescription: true,
        ),
        4,
      );
    });

    test('title 4 lines -> 2 desc lines', () {
      expect(
        ArticleTitleLayout.descriptionMaxLinesForCarousel(
          estimatedTitleLines: 4,
          hasImage: false,
          hasDescription: true,
        ),
        2,
      );
    });

    test('title 5 lines -> 1 desc line (keeps card height close to standard)',
        () {
      expect(
        ArticleTitleLayout.descriptionMaxLinesForCarousel(
          estimatedTitleLines: 5,
          hasImage: false,
          hasDescription: true,
        ),
        1,
      );
    });
  });

  group('ArticleTitleLayout.estimateDescriptionLines', () {
    test('returns 0 when maxLines is 0', () {
      expect(
        ArticleTitleLayout.estimateDescriptionLines(
          description: 'some description',
          availableWidth: 300,
          maxLines: 0,
        ),
        0,
      );
    });

    test('returns 0 when description is empty', () {
      expect(
        ArticleTitleLayout.estimateDescriptionLines(
          description: '',
          availableWidth: 300,
          maxLines: 4,
        ),
        0,
      );
    });

    test('clamps to maxLines for very long description', () {
      expect(
        ArticleTitleLayout.estimateDescriptionLines(
          description: 'x' * 1000,
          availableWidth: 300,
          maxLines: 4,
        ),
        4,
      );
    });
  });
}
