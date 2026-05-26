import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/flux_continu/models/flux_continu_models.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Shared fixtures
  // ---------------------------------------------------------------------------

  DigestTopicSection digestSection({
    SectionKind kind = SectionKind.essentiel,
    int topicCount = 3,
    int core = 3,
  }) {
    return DigestTopicSection(
      kind: kind,
      label: kind.name,
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

  FeedThemeSection themeSection({
    String? slug = 'tech',
    String? customTopicId,
    int itemCount = 2,
    int core = 2,
  }) {
    return FeedThemeSection(
      kind: SectionKind.theme,
      label: slug ?? 'Topic',
      accent: const Color(0xFF2C3E50),
      coreVisibleCount: core,
      themeSlug: slug,
      customTopicId: customTopicId,
      items: itemCount == 0
          ? const <Content>[]
          : List.generate(
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

  group('sectionKey', () {
    test('uses kind.name for digest sections', () {
      expect(sectionKey(digestSection(kind: SectionKind.essentiel)), 'essentiel');
      expect(sectionKey(digestSection(kind: SectionKind.bonnes)), 'bonnes');
    });

    test('disambiguates EssentielSection from legacy "Actus du jour"', () {
      // Story 9.2 hotfix — the v3 hi-fi card (EssentielSection) coexists
      // with the legacy DigestTopicSection now labelled "Actus du jour".
      // Both originally collapsed to 'essentiel'; we now route the v3 card
      // to its own key so per-section prefs survive without collision.
      const essentielV3 = EssentielSection(articles: []);
      expect(sectionKey(essentielV3), 'essentiel_v3');
      expect(
        sectionKey(digestSection(kind: SectionKind.essentiel)),
        'essentiel',
      );
    });

    test('uses theme:<slug> for theme favorites', () {
      expect(sectionKey(themeSection(slug: 'tech')), 'theme:tech');
      expect(sectionKey(themeSection(slug: 'science')), 'theme:science');
    });

    test('uses topic:<uuid> for custom topic favorites', () {
      expect(
        sectionKey(themeSection(slug: null, customTopicId: 'abc-uuid')),
        'topic:abc-uuid',
      );
    });

    test('falls back to theme:unknown for slug-less theme sections', () {
      expect(sectionKey(themeSection(slug: null)), 'theme:unknown');
    });
  });

  group('FluxContinuState', () {
    test('isOpen defaults to false', () {
      const state = FluxContinuState();
      expect(state.isOpen(digestSection()), isFalse);
      expect(state.isOpen(themeSection(slug: 'tech')), isFalse);
    });

    test('isOpen reads from moreOpen map keyed by sectionKey', () {
      final state = FluxContinuState(
        moreOpen: {sectionKey(digestSection(kind: SectionKind.bonnes)): true},
      );
      expect(state.isOpen(digestSection(kind: SectionKind.bonnes)), isTrue);
      expect(state.isOpen(digestSection(kind: SectionKind.essentiel)), isFalse);
    });

    test('isFolded defaults to false', () {
      const state = FluxContinuState();
      expect(state.isFolded(digestSection()), isFalse);
      expect(state.isFolded(themeSection(slug: 'tech')), isFalse);
    });

    test('isFolded reads from folded map keyed by sectionKey', () {
      const state = FluxContinuState(folded: {'essentiel': true});
      expect(state.isFolded(digestSection(kind: SectionKind.essentiel)), isTrue);
      expect(state.isFolded(digestSection(kind: SectionKind.bonnes)), isFalse);
    });

    test('copyWith preserves folded when not specified', () {
      const state = FluxContinuState(folded: {'theme:tech': true});
      final updated = state.copyWith(isSerene: true);
      expect(updated.isFolded(themeSection(slug: 'tech')), isTrue);
    });

    test('copyWith clears error when clearError is true', () {
      const state = FluxContinuState(error: 'boom');
      final updated = state.copyWith(clearError: true);
      expect(updated.error, isNull);
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

    test('copyWith updates folded independently of moreOpen', () {
      const state = FluxContinuState(
        moreOpen: {'bonnes': true},
        folded: {'essentiel': true},
      );
      final updated = state.copyWith(
        folded: const {'essentiel': true, 'theme:tech': true},
      );
      expect(updated.isOpen(digestSection(kind: SectionKind.bonnes)), isTrue);
      expect(updated.isFolded(digestSection(kind: SectionKind.essentiel)), isTrue);
      expect(updated.isFolded(themeSection(slug: 'tech')), isTrue);
    });
  });

  group('FluxSection.hasOverflow', () {
    test('DigestTopicSection: true when topics exceed coreVisibleCount', () {
      expect(digestSection(topicCount: 5, core: 2).hasOverflow, isTrue);
    });

    test('DigestTopicSection: false when topics equal coreVisibleCount', () {
      expect(digestSection(topicCount: 3, core: 3).hasOverflow, isFalse);
    });

    test('FeedThemeSection: true when items exceed coreVisibleCount', () {
      expect(themeSection(itemCount: 4, core: 2).hasOverflow, isTrue);
    });

    test('FeedThemeSection: totalCount reflects items length', () {
      expect(themeSection(itemCount: 5, core: 2).totalCount, 5);
    });

    test('blurb is optional and defaults to null', () {
      expect(digestSection(topicCount: 2, core: 2).blurb, isNull);
      expect(themeSection(itemCount: 2, core: 2).blurb, isNull);
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
    test('lists slugs from FeedThemeSections only', () {
      final state = FluxContinuState(
        sections: [
          digestSection(kind: SectionKind.essentiel),
          themeSection(slug: 'tech'),
          themeSection(slug: 'environment'),
        ],
      );
      expect(state.tourneeThemeSlugs, ['tech', 'environment']);
    });

    test('returns empty when no FeedThemeSection has a slug', () {
      const state = FluxContinuState();
      expect(state.tourneeThemeSlugs, isEmpty);
    });

    test('skips FeedThemeSections without a slug (custom topic only)', () {
      final state = FluxContinuState(
        sections: [
          themeSection(slug: null, customTopicId: 'abc-uuid'),
          themeSection(slug: 'science'),
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

  group('nextSectionAfter', () {
    test('returns the next section after the current one', () {
      final a = themeSection(slug: 'tech');
      final b = themeSection(slug: 'climat');
      final result = nextSectionAfter([a, b], sectionKey(a));
      expect(result, same(b));
    });

    test('skips EssentielSection between two theme sections', () {
      final a = themeSection(slug: 'tech');
      const essentiel = EssentielSection(articles: []);
      final b = themeSection(slug: 'climat');
      final result = nextSectionAfter([a, essentiel, b], sectionKey(a));
      expect(result, same(b));
    });

    test('returns null when current section is the last one', () {
      final a = themeSection(slug: 'tech');
      final b = themeSection(slug: 'climat');
      expect(nextSectionAfter([a, b], sectionKey(b)), isNull);
    });

    test('returns null for an unknown current key', () {
      final a = themeSection(slug: 'tech');
      expect(nextSectionAfter([a], 'theme:nope'), isNull);
    });
  });
}
