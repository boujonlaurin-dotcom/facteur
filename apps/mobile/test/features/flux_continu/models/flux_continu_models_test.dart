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

    test('isFolded defaults to false for any section', () {
      const state = FluxContinuState();
      expect(state.isFolded(SectionKind.essentiel), isFalse);
      expect(state.isFolded(SectionKind.bonnes), isFalse);
      expect(state.isFolded(SectionKind.theme1), isFalse);
      expect(state.isFolded(SectionKind.theme2), isFalse);
    });

    test('isFolded reads from folded map', () {
      const state = FluxContinuState(folded: {SectionKind.essentiel: true});
      expect(state.isFolded(SectionKind.essentiel), isTrue);
      expect(state.isFolded(SectionKind.bonnes), isFalse);
    });

    test('copyWith preserves folded when not specified', () {
      const state = FluxContinuState(folded: {SectionKind.theme1: true});
      final updated = state.copyWith(isSerene: true);
      expect(updated.isFolded(SectionKind.theme1), isTrue);
    });

    test('closingDismissed defaults to false', () {
      const state = FluxContinuState();
      expect(state.closingDismissed, isFalse);
    });

    test('copyWith updates closingDismissed', () {
      const state = FluxContinuState();
      final updated = state.copyWith(closingDismissed: true);
      expect(updated.closingDismissed, isTrue);
    });

    test('copyWith preserves closingDismissed when not specified', () {
      const state = FluxContinuState(closingDismissed: true);
      final updated = state.copyWith(isSerene: true);
      expect(updated.closingDismissed, isTrue);
    });

    test('copyWith updates folded independently of moreOpen', () {
      const state = FluxContinuState(
        moreOpen: {SectionKind.bonnes: true},
        folded: {SectionKind.essentiel: true},
      );
      final updated = state.copyWith(
        folded: const {SectionKind.essentiel: true, SectionKind.theme1: true},
      );
      expect(updated.isOpen(SectionKind.bonnes), isTrue);
      expect(updated.isFolded(SectionKind.essentiel), isTrue);
      expect(updated.isFolded(SectionKind.theme1), isTrue);
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

    test('blurb is optional and defaults to null', () {
      expect(digestSection(2, 2).blurb, isNull);
      expect(feedSection(2, 2).blurb, isNull);
    });

    test('blurb is preserved when provided', () {
      const section = DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Essentiel',
        blurb: 'lead-in copy',
        accent: Color(0xFFB0470A),
        coreVisibleCount: 2,
        topics: [],
      );
      expect(section.blurb, 'lead-in copy');
    });
  });

  group('FluxContinuState.tourneeThemeSlugs', () {
    FeedThemeSection theme(String slug) => FeedThemeSection(
          kind: SectionKind.theme1,
          label: slug,
          accent: const Color(0xFF000000),
          coreVisibleCount: 3,
          themeSlug: slug,
          items: const [],
        );

    test('lists slugs from FeedThemeSections only', () {
      const digest = DigestTopicSection(
        kind: SectionKind.essentiel,
        label: 'Essentiel',
        accent: Color(0xFFB0470A),
        coreVisibleCount: 3,
        topics: [],
      );
      final state = FluxContinuState(
        sections: [digest, theme('tech'), theme('environment')],
      );
      expect(state.tourneeThemeSlugs, ['tech', 'environment']);
    });

    test('returns empty when no FeedThemeSection has a slug', () {
      const state = FluxContinuState();
      expect(state.tourneeThemeSlugs, isEmpty);
    });

    test('skips FeedThemeSections without a slug', () {
      final state = FluxContinuState(
        sections: [
          const FeedThemeSection(
            kind: SectionKind.theme1,
            label: 'X',
            accent: Color(0xFF000000),
            coreVisibleCount: 3,
            items: [],
          ),
          theme('science'),
        ],
      );
      expect(state.tourneeThemeSlugs, ['science']);
    });
  });

  group('FluxContinuState.dismissedIds', () {
    test('defaults to empty set', () {
      const state = FluxContinuState();
      expect(state.dismissedIds, isEmpty);
    });

    test('copyWith updates dismissedIds', () {
      const state = FluxContinuState();
      final updated = state.copyWith(dismissedIds: {'a', 'b'});
      expect(updated.dismissedIds, {'a', 'b'});
    });

    test('copyWith preserves dismissedIds when not specified', () {
      const state = FluxContinuState(dismissedIds: {'x'});
      final updated = state.copyWith(isSerene: true);
      expect(updated.dismissedIds, {'x'});
    });
  });
}
