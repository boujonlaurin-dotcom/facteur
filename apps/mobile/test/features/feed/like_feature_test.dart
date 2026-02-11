import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';

void main() {
  group('Content isLiked', () {
    test('fromJson parses is_liked correctly', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Article',
        'url': 'https://example.com',
        'content_type': 'article',
        'published_at': '2026-02-11T10:00:00Z',
        'source': {
          'id': 'source-id',
          'name': 'Test Source',
          'logo_url': null,
          'type': 'article',
          'theme': 'tech',
        },
        'is_liked': true,
        'is_saved': false,
      };

      final content = Content.fromJson(json);
      expect(content.isLiked, isTrue);
    });

    test('fromJson defaults isLiked to false when missing', () {
      final json = {
        'id': 'test-id',
        'title': 'Test Article',
        'url': 'https://example.com',
        'content_type': 'article',
        'published_at': '2026-02-11T10:00:00Z',
        'source': {
          'id': 'source-id',
          'name': 'Test Source',
          'logo_url': null,
          'type': 'article',
          'theme': 'tech',
        },
      };

      final content = Content.fromJson(json);
      expect(content.isLiked, isFalse);
    });

    test('copyWith preserves isLiked when not specified', () {
      final content = Content(
        id: 'test-id',
        title: 'Test',
        url: 'https://example.com',
        contentType: ContentType.article,
        publishedAt: DateTime.now(),
        source: Source.fallback(),
        isLiked: true,
      );

      final copied = content.copyWith(isSaved: true);
      expect(copied.isLiked, isTrue);
      expect(copied.isSaved, isTrue);
    });

    test('copyWith updates isLiked', () {
      final content = Content(
        id: 'test-id',
        title: 'Test',
        url: 'https://example.com',
        contentType: ContentType.article,
        publishedAt: DateTime.now(),
        source: Source.fallback(),
        isLiked: false,
      );

      final liked = content.copyWith(isLiked: true);
      expect(liked.isLiked, isTrue);

      final unliked = liked.copyWith(isLiked: false);
      expect(unliked.isLiked, isFalse);
    });
  });
}
