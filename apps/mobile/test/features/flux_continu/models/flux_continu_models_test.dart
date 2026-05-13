import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pickTopicLead', () {
    DigestItem item(String id, {bool followed = false}) =>
        DigestItem(contentId: id, title: 't', isFollowedSource: followed);

    test('picks the first followed-source article when one exists', () {
      final topic = DigestTopic(
        topicId: 't1',
        label: 'Topic',
        articles: [item('a'), item('b', followed: true), item('c')],
      );
      expect(pickTopicLead(topic).contentId, 'b');
    });

    test('falls back to the first article when no followed source', () {
      final topic = DigestTopic(
        topicId: 't1',
        label: 'Topic',
        articles: [item('a'), item('b')],
      );
      expect(pickTopicLead(topic).contentId, 'a');
    });
  });

  group('FluxContinuState', () {
    test('isOpen defaults to false for any section', () {
      const state = FluxContinuState();
      expect(state.isOpen(SectionKind.essentiel), isFalse);
      expect(state.isOpen(SectionKind.bonnes), isFalse);
      expect(state.isOpen(SectionKind.theme1), isFalse);
      expect(state.isOpen(SectionKind.theme2), isFalse);
    });

    test('isOpen reads from moreOpen map', () {
      const state = FluxContinuState(moreOpen: {SectionKind.bonnes: true});
      expect(state.isOpen(SectionKind.bonnes), isTrue);
      expect(state.isOpen(SectionKind.essentiel), isFalse);
    });

    test('copyWith clears error when clearError is true', () {
      const state = FluxContinuState(error: 'boom');
      final updated = state.copyWith(clearError: true);
      expect(updated.error, isNull);
    });

    test('copyWith preserves untouched fields', () {
      const state = FluxContinuState(isSerene: true);
      final updated = state.copyWith(isLoading: false);
      expect(updated.isSerene, isTrue);
      expect(updated.isLoading, isFalse);
    });
  });

  group('FluxSection.hasOverflow', () {
    DigestTopicSection digestSection(int topicCount, int core) {
      return DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Essentiel',
        accent: const Color(0xFFB0470A),
        coreVisibleCount: core,
        topics: List.generate(
          topicCount,
          (i) => DigestTopic(
            topicId: 't$i',
            label: 'Topic $i',
            articles: [DigestItem(contentId: 'c$i', title: 't$i')],
          ),
        ),
      );
    }

    FeedThemeSection feedSection(int itemCount, int core) {
      return FeedThemeSection(
        kind: SectionKind.theme1,
        label: 'Tech',
        accent: const Color(0xFF2C3E50),
        coreVisibleCount: core,
        items: List.generate(
          itemCount,
          (i) => Content(
            id: 'c$i',
            title: 't$i',
            url: 'https://x.test/$i',
            contentType: ContentType.article,
            publishedAt: DateTime(2026, 1, 1),
            source: Source(id: 's', name: 'S', type: SourceType.article),
          ),
        ),
      );
    }

    test('DigestTopicSection: true when topics exceed coreVisibleCount', () {
      expect(digestSection(5, 2).hasOverflow, isTrue);
    });

    test('DigestTopicSection: false when topics equal coreVisibleCount', () {
      expect(digestSection(3, 3).hasOverflow, isFalse);
    });

    test('FeedThemeSection: true when items exceed coreVisibleCount', () {
      expect(feedSection(4, 2).hasOverflow, isTrue);
    });

    test('FeedThemeSection: totalCount reflects items length', () {
      expect(feedSection(5, 2).totalCount, 5);
    });
  });
}
