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

    test('uses source:<id> for source sections', () {
      const src = FeedThemeSection(
        kind: SectionKind.source,
        label: 'Le Monde',
        accent: Color(0xFF8E44AD),
        coreVisibleCount: 3,
        sourceId: 'src-uuid',
        sourceLogoUrl: 'https://logo.test/x.png',
        items: const <Content>[],
      );
      expect(sectionKey(src), 'source:src-uuid');
    });
  });

  group('FluxContinuState', () {
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

    test('FeedThemeSection: noRecentSource defaults to false', () {
      expect(themeSection().noRecentSource, isFalse);
    });

    test('FeedThemeSection: copyWith preserves noRecentSource', () {
      // Piège connu (cf. coreVisibleCount) : un champ oublié dans copyWith
      // disparaîtrait au 1er recompose. Ici on vérifie qu'il survit quand on
      // ne le redéfinit pas.
      final src = FeedThemeSection(
        kind: SectionKind.source,
        label: 'Le Monde',
        accent: const Color(0xFF2C3E50),
        coreVisibleCount: 3,
        sourceId: 's1',
        items: const <Content>[],
        noRecentSource: true,
      );
      final copy = src.copyWith(isLoadingMore: true);
      expect(copy.noRecentSource, isTrue);
      expect(src.copyWith(noRecentSource: false).noRecentSource, isFalse);
    });

    test('FeedThemeSection: followedSourceCount defaults to 0', () {
      expect(themeSection().followedSourceCount, 0);
    });

    test('FeedThemeSection: copyWith preserves followedSourceCount (Story 22.5)',
        () {
      // Risque n°1 du hand-off : `followedSourceCount` oublié dans copyWith
      // retomberait à 0 au 1er dédup/loadMore → CTA « Ajouter » sur une section
      // pourtant riche en sources suivies. On vérifie qu'il survit quand on ne
      // le redéfinit pas, et qu'un override explicite prime.
      final src = FeedThemeSection(
        kind: SectionKind.theme,
        label: 'Tech',
        accent: const Color(0xFF2C3E50),
        coreVisibleCount: 3,
        themeSlug: 'tech',
        items: const <Content>[],
        followedSourceCount: 7,
      );
      // Champ non redéfini → préservé à travers un copyWith orthogonal.
      expect(src.copyWith(isLoadingMore: true).followedSourceCount, 7);
      expect(src.copyWith(underfilled: true).followedSourceCount, 7);
      // Override explicite (re-stamp par _stampFollowedCounts) → prime.
      expect(src.copyWith(followedSourceCount: 2).followedSourceCount, 2);
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

    test('returns the next digest section after a theme section', () {
      // La section suivante peut être une section digest (Bonnes Nouvelles /
      // Actus du jour) — le footer route alors vers /section/ et non /theme/.
      final a = themeSection(slug: 'tech');
      final b = digestSection(kind: SectionKind.bonnes);
      final result = nextSectionAfter([a, b], sectionKey(a));
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

  // ---------------------------------------------------------------------------
  // Story 22.3 — suggestions « Choisie pour vous »
  // ---------------------------------------------------------------------------

  group('FeedThemeSection origin/reason (Story 22.3)', () {
    test('default origin is validated and reason is null', () {
      final s = themeSection(slug: 'tech');
      expect(s.origin, SectionOrigin.validated);
      expect(s.reason, isNull);
      expect(s.isSuggested, isFalse);
    });

    test('suggested section carries origin + reason', () {
      const reason = SuggestionReason(
        label: 'Tu suis ce thème',
        breakdown: [SuggestionContribution(label: 'Tu suis ce thème')],
      );
      const s = FeedThemeSection(
        kind: SectionKind.theme,
        label: 'Tech',
        accent: Color(0xFF000000),
        coreVisibleCount: 3,
        themeSlug: 'tech',
        items: [],
        origin: SectionOrigin.suggested,
        reason: reason,
      );
      expect(s.isSuggested, isTrue);
      expect(s.reason, same(reason));
    });

    test('copyWith preserves origin + reason (badge survives recompose)', () {
      const reason = SuggestionReason(label: 'Sources fiables');
      const s = FeedThemeSection(
        kind: SectionKind.source,
        label: 'Le Monde',
        accent: Color(0xFF000000),
        coreVisibleCount: 3,
        sourceId: 'sid',
        items: [],
        origin: SectionOrigin.suggested,
        reason: reason,
      );
      final copy = s.copyWith(items: const []);
      expect(copy.origin, SectionOrigin.suggested);
      expect(copy.reason, same(reason));
      expect(copy.isSuggested, isTrue);
    });
  });

  group('SuggestionReason.fromJson (Story 22.3)', () {
    test('parses label + breakdown', () {
      final r = SuggestionReason.fromJson({
        'label': 'Tu suis ce thème',
        'breakdown': [
          {'label': 'Tu suis ce thème', 'points': 100, 'pillar': 'pertinence'},
          {'label': '5 articles récents', 'points': 50, 'pillar': 'fraicheur'},
        ],
      });
      expect(r.label, 'Tu suis ce thème');
      expect(r.breakdown, hasLength(2));
      expect(r.breakdown.first.label, 'Tu suis ce thème');
      expect(r.breakdown.first.pillar, 'pertinence');
      expect(r.breakdown[1].points, 50);
    });

    test('tolerates missing breakdown', () {
      final r = SuggestionReason.fromJson({'label': 'Varié pour aujourd\'hui'});
      expect(r.label, 'Varié pour aujourd\'hui');
      expect(r.breakdown, isEmpty);
    });
  });

  group('EssentielArticle — couverture multi-sources', () {
    test('parses source_count + perspective_sources', () {
      final a = EssentielArticle.fromJson({
        'content_id': 'c-1',
        'title': 'Titre',
        'url': 'https://example.com',
        'published_at': '2026-07-30T08:00:00Z',
        'source': {'name': 'Le Monde'},
        'source_letter': 'L',
        'section_label': 'Climat',
        'rank': 1,
        'source_count': 4,
        'perspective_sources': [
          {'name': 'Le Monde', 'domain': 'lemonde.fr', 'bias_stance': 'center'},
          {'name': 'Libération', 'logo_url': 'https://x/l.png'},
        ],
      });
      expect(a.sourceCount, 4);
      expect(a.perspectiveSources, hasLength(2));
      expect(a.perspectiveSources.first.name, 'Le Monde');
      expect(a.perspectiveSources[1].logoUrl, 'https://x/l.png');
    });

    test('retro-compat : un snapshot Hive sans les champs parse en défauts', () {
      final a = EssentielArticle.fromJson({
        'content_id': 'c-1',
        'title': 'Titre',
        'url': 'https://example.com',
        'published_at': '2026-07-30T08:00:00Z',
        'source': {'name': 'Le Monde'},
        'source_letter': 'L',
        'section_label': 'Climat',
        'rank': 1,
      });
      expect(a.sourceCount, 0);
      expect(a.perspectiveSources, isEmpty);
    });
  });

  // ---------------------------------------------------------------------------
  // coverageCount — max(sourceCount, perspectiveCount) — bug « carte bloquée »
  // ---------------------------------------------------------------------------
  group('coverageCount', () {
    EssentielArticle article({int sourceCount = 0, int perspectiveCount = 0}) {
      return EssentielArticle(
        contentId: 'c',
        title: 't',
        url: 'https://example.com',
        publishedAt: DateTime(2026, 7, 30),
        sourceName: 'Le Monde',
        sourceLetter: 'L',
        sectionLabel: 'Climat',
        rank: 1,
        sourceCount: sourceCount,
        perspectiveCount: perspectiveCount,
      );
    }

    DigestTopic topic({int sourceCount = 0, int perspectiveCount = 0}) {
      return DigestTopic(
        topicId: 't',
        label: 'Topic',
        sourceCount: sourceCount,
        perspectiveCount: perspectiveCount,
      );
    }

    test('EssentielArticle : perspective (reader) > source (ranking figé)', () {
      expect(article(sourceCount: 2, perspectiveCount: 7).coverageCount, 7);
    });

    test('EssentielArticle : source >= perspective → source', () {
      expect(article(sourceCount: 5, perspectiveCount: 3).coverageCount, 5);
    });

    test('EssentielArticle : égaux → la valeur commune', () {
      expect(article(sourceCount: 4, perspectiveCount: 4).coverageCount, 4);
    });

    test('DigestTopic : perspective (reader) > source (ranking figé)', () {
      expect(topic(sourceCount: 2, perspectiveCount: 8).coverageCount, 8);
    });

    test('DigestTopic : source >= perspective → source', () {
      expect(topic(sourceCount: 6, perspectiveCount: 1).coverageCount, 6);
    });
  });

  // ---------------------------------------------------------------------------
  // EssentielArticle.fromContent — adaptateur carrousel → article triable
  // (« Voir d'autres articles », itération PO 33.1)
  // ---------------------------------------------------------------------------
  group('EssentielArticle.fromContent', () {
    Content content({
      String id = 'x-1',
      String name = 'Le Monde',
      String sourceId = 's-1',
      ContentStatus status = ContentStatus.unseen,
    }) =>
        Content(
          id: id,
          title: 'Titre carrousel',
          url: 'https://example.com/$id',
          thumbnailUrl: 'https://example.com/$id.jpg',
          description: 'Un chapô.',
          contentType: ContentType.article,
          publishedAt: DateTime(2026, 8, 6),
          source: Source(id: sourceId, name: name, type: SourceType.article),
          status: status,
          isSaved: true,
          isFollowedSource: true,
        );

    test('reprend les champs adressables du Content', () {
      final a = EssentielArticle.fromContent(content(), rank: 6);
      expect(a.contentId, 'x-1');
      expect(a.title, 'Titre carrousel');
      expect(a.url, 'https://example.com/x-1');
      expect(a.thumbnailUrl, 'https://example.com/x-1.jpg');
      expect(a.description, 'Un chapô.');
      expect(a.sourceName, 'Le Monde');
      expect(a.sourceId, 's-1');
      expect(a.sourceLetter, 'L');
      expect(a.rank, 6);
      expect(a.isSaved, isTrue);
      expect(a.isFollowedSource, isTrue);
    });

    test('les signaux propres à l\'Essentiel retombent en défaut → pied muet',
        () {
      final a = EssentielArticle.fromContent(content(), rank: 6);
      // Couverture / divergence absentes du carrousel : la carte de tri ne
      // rendra ni puce couverture ni badge de polarisation.
      expect(a.coverageCount, 0);
      expect(a.divergenceLevel, isNull);
      expect(a.perspectiveSources, isEmpty);
      expect(a.isActuDuJour, isFalse);
    });

    test('un source.id vide devient null (pas de fausse découpe CTR)', () {
      final a = EssentielArticle.fromContent(content(sourceId: ''), rank: 6);
      expect(a.sourceId, isNull);
    });

    test('status consommé → isRead', () {
      final read = EssentielArticle.fromContent(
        content(status: ContentStatus.consumed),
        rank: 6,
      );
      expect(read.isRead, isTrue);
      final unread = EssentielArticle.fromContent(content(), rank: 6);
      expect(unread.isRead, isFalse);
    });
  });
}
