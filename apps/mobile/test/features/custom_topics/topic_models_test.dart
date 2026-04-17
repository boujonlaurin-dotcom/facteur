import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/sources/models/source_model.dart';

void main() {
  group('UserTopicProfile', () {
    test('fromJson parses complete response', () {
      final json = {
        'id': 'uuid-123',
        'topic_name': 'Mobilite douce',
        'slug_parent': 'climate',
        'keywords': ['velo', 'transport en commun'],
        'intent_description': 'Suivi des actualites sur la mobilite',
        'priority_multiplier': 1.5,
        'composite_score': 42,
        'source_type': 'explicit',
        'created_at': '2026-03-02T10:00:00Z',
      };

      final profile = UserTopicProfile.fromJson(json);

      expect(profile.id, 'uuid-123');
      expect(profile.name, 'Mobilite douce');
      expect(profile.slugParent, 'climate');
      expect(profile.keywords, ['velo', 'transport en commun']);
      expect(profile.intentDescription, 'Suivi des actualites sur la mobilite');
      expect(profile.priorityMultiplier, 1.5);
      expect(profile.compositeScore, 42);
      expect(profile.sourceType, TopicSourceType.explicit);
      expect(profile.createdAt, isNotNull);
    });

    test('fromJson handles minimal response with defaults', () {
      final json = {
        'id': 'uuid-456',
        'topic_name': 'IA',
      };

      final profile = UserTopicProfile.fromJson(json);

      expect(profile.id, 'uuid-456');
      expect(profile.name, 'IA');
      expect(profile.slugParent, isNull);
      expect(profile.keywords, isEmpty);
      expect(profile.intentDescription, isNull);
      expect(profile.priorityMultiplier, 1.0);
      expect(profile.compositeScore, 0);
      expect(profile.sourceType, TopicSourceType.explicit);
      expect(profile.createdAt, isNull);
    });

    test('fromJson handles implicit source type', () {
      final json = {
        'id': 'uuid-789',
        'topic_name': 'Crypto',
        'source_type': 'implicit',
      };

      final profile = UserTopicProfile.fromJson(json);
      expect(profile.sourceType, TopicSourceType.implicit);
    });

    test('fromJson handles suggested source type', () {
      final json = {
        'id': 'uuid-101',
        'topic_name': 'Startups',
        'source_type': 'suggested',
      };

      final profile = UserTopicProfile.fromJson(json);
      expect(profile.sourceType, TopicSourceType.suggested);
    });

    test('fromJson defaults unknown source_type to explicit', () {
      final json = {
        'id': 'uuid-102',
        'topic_name': 'Unknown',
        'source_type': 'future_new_type',
      };

      final profile = UserTopicProfile.fromJson(json);
      expect(profile.sourceType, TopicSourceType.explicit);
    });

    test('copyWith updates priority_multiplier', () {
      const original = UserTopicProfile(id: 'a', name: 'Test');
      final updated = original.copyWith(priorityMultiplier: 2.0);

      expect(updated.priorityMultiplier, 2.0);
      expect(updated.id, 'a');
      expect(updated.name, 'Test');
    });

    test('copyWith preserves all fields when updating one', () {
      const original = UserTopicProfile(
        id: 'a',
        name: 'IA',
        slugParent: 'tech',
        keywords: ['gpt', 'llm'],
        intentDescription: 'AI news',
        priorityMultiplier: 1.5,
        compositeScore: 50,
        sourceType: TopicSourceType.implicit,
      );

      final updated = original.copyWith(compositeScore: 75);

      expect(updated.id, 'a');
      expect(updated.name, 'IA');
      expect(updated.slugParent, 'tech');
      expect(updated.keywords, ['gpt', 'llm']);
      expect(updated.intentDescription, 'AI news');
      expect(updated.priorityMultiplier, 1.5);
      expect(updated.compositeScore, 75);
      expect(updated.sourceType, TopicSourceType.implicit);
    });

    test('equality works for identical profiles', () {
      const a = UserTopicProfile(id: 'x', name: 'Test');
      const b = UserTopicProfile(id: 'x', name: 'Test');

      expect(a, equals(b));
    });

    test('equality fails for different profiles', () {
      const a = UserTopicProfile(id: 'x', name: 'Test');
      const b = UserTopicProfile(id: 'y', name: 'Test');

      expect(a, isNot(equals(b)));
    });
  });

  group('FeedCluster', () {
    test('fromJson parses complete cluster data', () {
      final json = {
        'topic_slug': 'ai',
        'topic_name': 'Intelligence Artificielle',
        'representative_id': 'uuid-article-1',
        'hidden_count': 4,
        'hidden_ids': ['uuid-2', 'uuid-3', 'uuid-4', 'uuid-5'],
      };

      final cluster = FeedCluster.fromJson(json);

      expect(cluster.topicSlug, 'ai');
      expect(cluster.topicName, 'Intelligence Artificielle');
      expect(cluster.representativeId, 'uuid-article-1');
      expect(cluster.hiddenCount, 4);
      expect(cluster.hiddenIds.length, 4);
      expect(cluster.hiddenIds[0], 'uuid-2');
    });

    test('fromJson handles missing fields with defaults', () {
      final json = <String, dynamic>{};

      final cluster = FeedCluster.fromJson(json);

      expect(cluster.topicSlug, '');
      expect(cluster.topicName, '');
      expect(cluster.representativeId, '');
      expect(cluster.hiddenCount, 0);
      expect(cluster.hiddenIds, isEmpty);
    });

    test('fromJson handles partial data', () {
      final json = {
        'topic_slug': 'climate',
        'representative_id': 'art-1',
      };

      final cluster = FeedCluster.fromJson(json);

      expect(cluster.topicSlug, 'climate');
      expect(cluster.topicName, '');
      expect(cluster.representativeId, 'art-1');
      expect(cluster.hiddenCount, 0);
    });
  });

  // DEADCODE: Test masqué car champs commentés dans modèle Content
  /*
  group('Content cluster fields', () {
    test('default cluster fields are null/zero/empty', () {
      final content = Content(
        id: 'c1',
        title: 'Article',
        url: 'https://example.com',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 3, 2),
        source: Source.fallback(),
      );

      expect(content.clusterTopic, isNull);
      expect(content.clusterHiddenCount, 0);
      expect(content.clusterHiddenArticles, isEmpty);
    });

    test('copyWith preserves cluster fields when updating other fields', () {
      final content = Content(
        id: 'c1',
        title: 'Article',
        url: 'https://example.com',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 3, 2),
        source: Source.fallback(),
        clusterTopic: 'ai',
        clusterHiddenCount: 3,
      );

      final updated = content.copyWith(isSaved: true);

      expect(updated.clusterTopic, 'ai');
      expect(updated.clusterHiddenCount, 3);
      expect(updated.isSaved, isTrue);
    });

    test('copyWith can update cluster fields', () {
      final content = Content(
        id: 'c1',
        title: 'Article',
        url: 'https://example.com',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 3, 2),
        source: Source.fallback(),
      );

      final updated = content.copyWith(
        clusterTopic: 'climate',
        clusterHiddenCount: 5,
      );

      expect(updated.clusterTopic, 'climate');
      expect(updated.clusterHiddenCount, 5);
      expect(updated.id, 'c1');
    });

    test('clearNote preserves cluster fields', () {
      final content = Content(
        id: 'c1',
        title: 'Article',
        url: 'https://example.com',
        contentType: ContentType.article,
        publishedAt: DateTime(2026, 3, 2),
        source: Source.fallback(),
        noteText: 'My note',
        clusterTopic: 'ai',
        clusterHiddenCount: 2,
      );

      final cleared = content.clearNote();

      expect(cleared.noteText, isNull);
      expect(cleared.clusterTopic, 'ai');
      expect(cleared.clusterHiddenCount, 2);
    });
  });
  */

  group('FeedResponse with clusters', () {
    test('fromJson parses items and clusters', () {
      final json = {
        'items': [
          {
            'id': 'article-1',
            'title': 'AI News',
            'url': 'https://example.com',
            'content_type': 'article',
            'published_at': '2026-03-02T10:00:00Z',
            'source': {'id': 's1', 'topic_name': 'TechCrunch', 'type': 'article'},
          }
        ],
        'clusters': [
          {
            'topic_slug': 'ai',
            'topic_name': 'Intelligence Artificielle',
            'representative_id': 'article-1',
            'hidden_count': 2,
            'hidden_ids': ['article-2', 'article-3'],
          }
        ],
      };

      final response = FeedResponse.fromJson(json);

      expect(response.items.length, 1);
      expect(response.clusters.length, 1);
      expect(response.clusters[0].topicSlug, 'ai');
      expect(response.clusters[0].hiddenCount, 2);
    });

    test('fromJson defaults clusters to empty list when absent', () {
      final json = <String, dynamic>{
        'items': <dynamic>[],
      };

      final response = FeedResponse.fromJson(json);
      expect(response.clusters, isEmpty);
    });

    test('fromJson handles null clusters gracefully', () {
      final json = <String, dynamic>{
        'items': <dynamic>[],
        'clusters': null,
      };

      final response = FeedResponse.fromJson(json);
      expect(response.clusters, isEmpty);
    });
  });
}
