import 'dart:convert';

import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// These tests exercise the pure article-list builder side of WidgetService.
/// We test it via a thin local copy of the picker logic; the production code
/// path also writes to SharedPreferences via `home_widget`, which requires the
/// platform channel and is not exercised in unit tests.
void main() {
  group('Digest → widget article shape', () {
    test('first topic article gets is_main=true', () {
      final digest = _digest(topics: [
        _topic(label: 'International', articles: [_article('a1', 'Title 1')]),
        _topic(label: 'Tech', articles: [_article('a2', 'Title 2')]),
      ]);

      final picked = _pickList(digest);
      expect(picked.length, 2);
      expect(picked[0]['id'], 'a1');
      expect(picked[0]['is_main'], isTrue);
      expect(picked[0]['rank'], 1);
      expect(picked[0]['topic_label'], 'International');
      expect(picked[1]['is_main'], isFalse);
      expect(picked[1]['rank'], 2);
    });

    test('caps at 5 articles even with more topics', () {
      final topics = List.generate(
        7,
        (i) => _topic(label: 'T$i', articles: [_article('id$i', 'Title $i')]),
      );
      final digest = _digest(topics: topics);
      final picked = _pickList(digest);
      expect(picked.length, 5);
    });

    test('skips topics with no articles', () {
      final digest = _digest(topics: [
        _topic(label: 'Empty', articles: []),
        _topic(label: 'OK', articles: [_article('a1', 'Has article')]),
      ]);
      final picked = _pickList(digest);
      expect(picked.length, 1);
      expect(picked[0]['id'], 'a1');
    });

    test('prefers a followed-source article inside a topic', () {
      final digest = _digest(topics: [
        _topic(label: 'Mixed', articles: [
          _article('first', 'First'),
          _article('followed', 'Followed', isFollowedSource: true),
        ]),
      ]);
      final picked = _pickList(digest);
      expect(picked.length, 1);
      expect(picked[0]['id'], 'followed');
    });

    test('encodes to valid JSON parseable on the Kotlin side', () {
      final digest = _digest(topics: [
        _topic(label: 'International', articles: [_article('a1', 'T')]),
      ]);
      final picked = _pickList(digest);
      final encoded = jsonEncode(picked);
      final decoded = jsonDecode(encoded) as List<dynamic>;
      expect(decoded.length, 1);
      expect((decoded.first as Map)['id'], 'a1');
      expect((decoded.first as Map).containsKey('is_main'), isTrue);
      expect((decoded.first as Map).containsKey('topic_label'), isTrue);
      expect((decoded.first as Map).containsKey('perspective_count'), isTrue);
    });
  });
}

// ──────────────────────────────────────────────────────────────
// Reference picker — keeps tests independent from SharedPreferences
// ──────────────────────────────────────────────────────────────

const _maxArticles = 5;

List<Map<String, dynamic>> _pickList(DigestResponse digest) {
  final result = <Map<String, dynamic>>[];
  var rank = 1;
  for (final topic in digest.topics) {
    if (result.length >= _maxArticles) break;
    if (topic.articles.isEmpty) continue;
    final article = _pickSingleton(topic);
    if (article.isDismissed) continue;
    result.add({
      'id': article.contentId,
      'rank': rank,
      'topic_id': topic.topicId,
      'topic_label': topic.label,
      'is_main': rank == 1,
      'title': article.title,
      'source_name': article.source?.name ?? '',
      'source_logo_path': '',
      'thumbnail_path': '',
      'perspective_count': topic.perspectiveCount,
      'published_at_iso': article.publishedAt?.toUtc().toIso8601String() ?? '',
    });
    rank++;
  }
  return result;
}

DigestItem _pickSingleton(DigestTopic topic) {
  for (final a in topic.articles) {
    if (a.isFollowedSource) return a;
  }
  return topic.articles.first;
}

// ──────────────────────────────────────────────────────────────
// Test fixtures
// ──────────────────────────────────────────────────────────────

DigestResponse _digest({required List<DigestTopic> topics}) {
  return DigestResponse(
    digestId: 'test-digest',
    userId: 'u1',
    targetDate: DateTime.utc(2026, 4, 26),
    generatedAt: DateTime.utc(2026, 4, 26),
    topics: topics,
  );
}

DigestTopic _topic({
  required String label,
  required List<DigestItem> articles,
}) {
  return DigestTopic(
    topicId: 'topic-${label.toLowerCase()}',
    label: label,
    articles: articles,
    perspectiveCount: articles.length > 1 ? articles.length - 1 : 0,
  );
}

DigestItem _article(
  String id,
  String title, {
  bool isFollowedSource = false,
  ContentType type = ContentType.article,
}) {
  return DigestItem(
    contentId: id,
    title: title,
    contentType: type,
    isFollowedSource: isFollowedSource,
    source: const SourceMini(id: 's1', name: 'Le Monde'),
    publishedAt: DateTime.utc(2026, 4, 26, 7, 30),
  );
}
