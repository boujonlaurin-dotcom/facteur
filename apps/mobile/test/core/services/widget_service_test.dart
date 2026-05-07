import 'dart:convert';

import 'package:facteur/config/topic_labels.dart';
import 'package:facteur/core/services/widget_service.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';
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

  group('Feed → widget article shape', () {
    test('preserves order, ranks from 1, is_main always false', () {
      final items = [
        _content('c1', 'Première'),
        _content('c2', 'Deuxième'),
        _content('c3', 'Troisième'),
      ];
      final picked = _pickFeedList(items);
      expect(picked.map((e) => e['id']), ['c1', 'c2', 'c3']);
      expect(picked.map((e) => e['rank']), [1, 2, 3]);
      expect(picked.every((e) => e['is_main'] == false), isTrue);
    });

    test('caps at 80 items even with longer feed', () {
      final items = List.generate(120, (i) => _content('c$i', 'T$i'));
      final picked = _pickFeedList(items);
      expect(picked.length, 80);
      expect(picked.last['id'], 'c79');
    });

    test('thumbnail_path is always empty (Flux is image-less)', () {
      final items = List.generate(5, (i) => _content('c$i', 'T$i'));
      final picked = _pickFeedList(items);
      expect(picked.every((e) => e['thumbnail_path'] == ''), isTrue);
    });

    test('maps known topic slug to French label, falls back to empty', () {
      final picked = _pickFeedList([
        _content('c1', 'Tech', topics: ['ai']),
        _content('c2', 'Inconnu', topics: ['totally-unknown-slug']),
        _content('c3', 'Sans topic', topics: []),
      ]);
      expect(picked[0]['topic_label'], topicSlugToLabel['ai']);
      expect(picked[1]['topic_label'], '');
      expect(picked[2]['topic_label'], '');
    });

    test('source name + published_at_iso round-trip via JSON', () {
      final items = [
        _content('c1', 'Titre', sourceName: 'Le Monde'),
      ];
      final picked = _pickFeedList(items);
      final encoded = jsonEncode(picked);
      final decoded = jsonDecode(encoded) as List<dynamic>;
      final first = decoded.first as Map<String, dynamic>;
      expect(first['source_name'], 'Le Monde');
      expect((first['published_at_iso'] as String).endsWith('Z'), isTrue);
      expect(first['perspective_count'], 0);
    });
  });

  group('Merge — Essentiel-then-Flux unified payload', () {
    Map<String, dynamic> entry(String id, {int rank = 1, bool isMain = false}) {
      return {
        'id': id,
        'rank': rank,
        'topic_id': 't',
        'topic_label': 'Topic',
        'is_main': isMain,
        'title': 'Title $id',
        'source_name': 'Source',
        'source_logo_path': '',
        'thumbnail_path': '',
        'perspective_count': 0,
        'published_at_iso': '',
      };
    }

    test('Essentiel comes first, then Flux', () {
      final merged = WidgetService.mergeForWidget(
        [entry('e1'), entry('e2')],
        [entry('f1'), entry('f2')],
      );
      expect(merged.map((e) => e['id']), ['e1', 'e2', 'f1', 'f2']);
    });

    test('every entry carries source_kind', () {
      final merged = WidgetService.mergeForWidget(
        [entry('e1')],
        [entry('f1')],
      );
      expect(merged[0]['source_kind'], 'essentiel');
      expect(merged[1]['source_kind'], 'flux');
    });

    test('Flux entries duplicating an Essentiel id are dropped', () {
      final merged = WidgetService.mergeForWidget(
        [entry('shared'), entry('e2')],
        [entry('shared'), entry('f2')],
      );
      // shared appears only once, tagged as essentiel, then e2, then f2.
      expect(merged.map((e) => e['id']), ['shared', 'e2', 'f2']);
      expect(merged.first['source_kind'], 'essentiel');
    });

    test('total cap at 80, Essentiel always wins on collision', () {
      final essentiel =
          List.generate(5, (i) => entry('e$i', rank: i + 1, isMain: i == 0));
      final flux = List.generate(120, (i) => entry('f$i', rank: i + 1));
      final merged = WidgetService.mergeForWidget(essentiel, flux);
      expect(merged.length, 80);
      expect(merged.first['id'], 'e0');
      expect(merged.first['source_kind'], 'essentiel');
      expect(merged[5]['id'], 'f0');
      expect(merged[5]['source_kind'], 'flux');
    });

    test('empty inputs yield empty output', () {
      expect(WidgetService.mergeForWidget(const [], const []), isEmpty);
    });

    test('entries with empty id are skipped', () {
      final merged = WidgetService.mergeForWidget(
        [entry(''), entry('e1')],
        [entry(''), entry('f1')],
      );
      expect(merged.map((e) => e['id']), ['e1', 'f1']);
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

// ──────────────────────────────────────────────────────────────
// Feed reference picker — mirrors WidgetService._buildFeedArticleList
// without the SharedPreferences/dio image fetch dependencies.
// ──────────────────────────────────────────────────────────────

const _maxFeedArticles = 80;

List<Map<String, dynamic>> _pickFeedList(List<Content> items) {
  final capped = items.take(_maxFeedArticles).toList();
  final result = <Map<String, dynamic>>[];
  for (var i = 0; i < capped.length; i++) {
    final item = capped[i];
    final topicSlug = item.topics.isNotEmpty ? item.topics.first : '';
    final topicLabel = topicSlugToLabel[topicSlug] ?? '';
    result.add({
      'id': item.id,
      'rank': i + 1,
      'topic_id': topicSlug,
      'topic_label': topicLabel,
      'is_main': false,
      'title': item.title,
      'source_name': item.source.name,
      'source_logo_path': '',
      'thumbnail_path': '',
      'perspective_count': 0,
      'published_at_iso': item.publishedAt.toUtc().toIso8601String(),
    });
  }
  return result;
}

Content _content(
  String id,
  String title, {
  String sourceName = 'Le Monde',
  List<String> topics = const [],
}) {
  return Content(
    id: id,
    title: title,
    url: 'https://example.com/$id',
    contentType: ContentType.article,
    publishedAt: DateTime.utc(2026, 5, 6, 9, 0),
    source: Source(
      id: 's1',
      name: sourceName,
      type: SourceType.article,
    ),
    topics: topics,
  );
}
