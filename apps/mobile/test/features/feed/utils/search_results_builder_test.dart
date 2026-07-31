import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/feed/models/search_result.dart';
import 'package:facteur/features/feed/utils/search_results_builder.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter_test/flutter_test.dart';

Source _source(
  String id,
  String name, {
  bool isTrusted = false,
  bool isCustom = false,
  bool isMuted = false,
  String? url,
}) =>
    Source(
      id: id,
      name: name,
      url: url,
      type: SourceType.article,
      isTrusted: isTrusted,
      isCustom: isCustom,
      isMuted: isMuted,
    );

UserTopicProfile _topic(
  String id,
  String name, {
  String? slugParent,
  String? entityType,
  String? canonicalName,
}) =>
    UserTopicProfile(
      id: id,
      name: name,
      slugParent: slugParent,
      entityType: entityType,
      canonicalName: canonicalName,
    );

SearchSection? _section(List<SearchSection> sections, String title) {
  for (final s in sections) {
    if (s.title == title) return s;
  }
  return null;
}

void main() {
  final followed = _source('s1', 'Mediapart', isTrusted: true);
  final custom = _source('s2', 'Blog perso', isCustom: true);
  final catalog = _source('s3', 'Le Monde', url: 'https://lemonde.fr');
  final muted = _source('s4', 'Le Figaro', isTrusted: true, isMuted: true);
  final allSources = [followed, custom, catalog, muted];

  final topics = [
    _topic('t1', 'Écologie', slugParent: 'environment'),
    _topic(
      't2',
      'Emmanuel Macron',
      entityType: 'person',
      canonicalName: 'Emmanuel Macron',
    ),
  ];

  group('isFollowedSource', () {
    test('trusted ou custom, non mis en sourdine', () {
      expect(isFollowedSource(followed), isTrue);
      expect(isFollowedSource(custom), isTrue);
      expect(isFollowedSource(catalog), isFalse);
      expect(isFollowedSource(muted), isFalse);
    });
  });

  group('buildSearchSections', () {
    test('requête vide → aucune section', () {
      expect(
        buildSearchSections(query: '  ', allSources: allSources, topics: topics),
        isEmpty,
      );
    });

    test('requête libre → « Articles » en tête', () {
      final sections = buildSearchSections(
        query: 'retraites',
        allSources: allSources,
        topics: topics,
      );
      expect(sections.first.title, kSectionArticles);
      expect(sections.first.results.single, isA<KeywordResult>());
    });

    test('« Chercher une source » est toujours proposée', () {
      final sections = buildSearchSections(
        query: 'retraites',
        allSources: allSources,
        topics: topics,
      );
      final add = _section(sections, kSectionAddSource);
      expect(add, isNotNull);
      expect(add!.results.last, isA<AddSourceResult>());
    });

    test('une source suivie remonte dans « Tes sources »', () {
      final sections = buildSearchSections(
        query: 'media',
        allSources: allSources,
        topics: topics,
      );
      final sources = _section(sections, kSectionSources);
      expect(sources, isNotNull);
      final result = sources!.results.single as FollowedSourceResult;
      expect(result.source.id, 's1');
    });

    test('une source du catalogue non suivie va dans « Chercher une source »',
        () {
      final sections = buildSearchSections(
        query: 'Le Monde',
        allSources: allSources,
        topics: topics,
      );
      final add = _section(sections, kSectionAddSource)!;
      final catalogResult = add.results.first as CatalogSourceResult;
      expect(catalogResult.source.id, 's3');
      // Elle n'apparaît pas comme source filtrable tant qu'elle n'est pas suivie.
      expect(_section(sections, kSectionSources), isNull);
    });

    test('une source en sourdine n\'est jamais reproposée', () {
      final sections = buildSearchSections(
        query: 'Figaro',
        allSources: allSources,
        topics: topics,
      );
      expect(_section(sections, kSectionSources), isNull);
      final add = _section(sections, kSectionAddSource)!;
      expect(add.results.whereType<CatalogSourceResult>(), isEmpty);
    });

    test('match exact sur une source → intention source, articles en dernier',
        () {
      final sections = buildSearchSections(
        query: 'mediapart',
        allSources: allSources,
        topics: topics,
      );
      expect(sections.first.title, kSectionSources);
      expect(sections.last.title, kSectionArticles);
    });

    test('un domaine saisi bascule aussi en intention source', () {
      final sections = buildSearchSections(
        query: 'lemonde.fr',
        allSources: allSources,
        topics: topics,
      );
      expect(sections.first.title, anyOf(kSectionSources, kSectionAddSource));
      expect(sections.last.title, kSectionArticles);
    });

    test('les sujets suivis matchent malgré les accents', () {
      final sections = buildSearchSections(
        query: 'ecolo',
        allSources: allSources,
        topics: topics,
      );
      final subjects = _section(sections, kSectionTopics)!;
      final result = subjects.results.single as TopicResult;
      expect(result.topic.name, 'Écologie');
      expect(result.isEntity, isFalse);
      expect(result.filterValue, 'environment');
    });

    test('une entité suivie se filtre par nom canonique', () {
      final sections = buildSearchSections(
        query: 'macron',
        allSources: allSources,
        topics: topics,
      );
      final result =
          _section(sections, kSectionTopics)!.results.single as TopicResult;
      expect(result.isEntity, isTrue);
      expect(result.filterValue, 'Emmanuel Macron');
    });

    test('les macro-thèmes sont proposés avec leur slug API', () {
      final sections = buildSearchSections(
        query: 'environnement',
        allSources: allSources,
        topics: topics,
      );
      final themes = _section(sections, kSectionThemes)!;
      final result = themes.results.single as ThemeResult;
      expect(result.label, 'Environnement');
      expect(result.slug, 'environment');
      expect(result.emoji, isNotEmpty);
    });

    test('perSectionLimit borne chaque section et hasMore le signale', () {
      final many = [
        for (var i = 0; i < 6; i++)
          _source('m$i', 'Media $i', isTrusted: true),
      ];
      final sections = buildSearchSections(
        query: 'media',
        allSources: many,
        topics: const [],
        perSectionLimit: 2,
      );
      final sources = _section(sections, kSectionSources)!;
      expect(sources.results, hasLength(2));
      expect(sources.totalMatches, 6);
      expect(sources.hasMore, isTrue);
      // « Voir tout » déplie depuis `allResults`, sans second calcul.
      expect(sources.allResults, hasLength(6));
    });

    test('« ajouter une source » ne se dit tronquée que si elle l\'est', () {
      final sections = buildSearchSections(
        query: 'gazette',
        allSources: [
          _source('c1', 'Gazette du Nord'),
          _source('c2', 'Gazette du Sud'),
        ],
        topics: const [],
      );
      final add = _section(sections, kSectionAddSource)!;
      // 2 catalogues + la recherche intelligente : tout est affiché.
      expect(add.results, hasLength(3));
      expect(add.hasMore, isFalse);
    });

    test('un match exact non classé premier bascule quand même en intention '
        'source', () {
      final sections = buildSearchSections(
        query: 'le monde',
        allSources: [
          _source('x1', 'Le Monde diplomatique', isTrusted: true),
          _source('x2', 'Le Monde', isTrusted: true),
        ],
        topics: const [],
      );
      expect(sections.first.title, kSectionSources);
      expect(sections.last.title, kSectionArticles);
    });
  });
}
