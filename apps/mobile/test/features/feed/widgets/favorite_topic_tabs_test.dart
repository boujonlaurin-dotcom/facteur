import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/providers/custom_topics_provider.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/widgets/favorite_topic_tabs.dart';
import 'package:facteur/features/my_interests/models/user_interests_state.dart';
import 'package:facteur/features/my_interests/models/user_sources_state.dart';
import 'package:facteur/features/my_interests/providers/user_interests_provider.dart';
import 'package:facteur/features/sources/models/source_model.dart';

Source _source({required String id, required String name}) =>
    Source.fallback().copyWith(id: id, name: name);

UserTopicProfile _topic({
  required String id,
  required String name,
  String? slugParent,
  double priorityMultiplier = 1.0,
  String? entityType,
  String? canonicalName,
  double compositeScore = 0.0,
}) {
  return UserTopicProfile(
    id: id,
    name: name,
    slugParent: slugParent,
    priorityMultiplier: priorityMultiplier,
    entityType: entityType,
    canonicalName: canonicalName,
    compositeScore: compositeScore,
  );
}

Content _content({
  required String id,
  required List<String> topics,
  ContentStatus status = ContentStatus.unseen,
  Duration ageBeforeNow = const Duration(hours: 1),
  List<ContentEntity> entities = const [],
}) {
  return Content(
    id: id,
    title: 'Title $id',
    url: 'https://example.com/$id',
    contentType: ContentType.article,
    publishedAt: DateTime.now().subtract(ageBeforeNow),
    source: Source.fallback(),
    status: status,
    topics: topics,
    entities: entities,
  );
}

void main() {
  group('buildFavoriteTabModelsForTest', () {
    test('0 favoris → aucun onglet (« Tous » supprimé)', () {
      final tabs = buildFavoriteTabModelsForTest(
        topics: const [],
        favorites: const [],
        items: const [],
      );

      expect(tabs, isEmpty);
    });

    test(
        '2 sujets + 1 thème favori → seuls les sujets sont des onglets '
        '(le thème pilote la Tournée, pas un onglet Flâner)', () {
      final topics = [
        _topic(
          id: 't1',
          name: 'IA santé',
          slugParent: 'ai-health',
        ),
        _topic(
          id: 't2',
          name: 'Trump',
          entityType: 'PERSON',
          canonicalName: 'Donald Trump',
          compositeScore: 0.8,
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: const [
          CustomTopicFavoriteRef(id: 't1'),
          CustomTopicFavoriteRef(id: 't2'),
          ThemeFavoriteRef(slug: 'environment'),
        ],
        items: const [],
      );

      // Le thème favori (environment) ne produit PAS d'onglet, et « Tous » est
      // supprimé : seuls les 2 sujets épinglés sont présents. Plus de tri par
      // count → ordre d'insertion : entités d'abord, puis sujets.
      expect(tabs.map((t) => t.kind).toList(), [
        FavoriteTabKind.subjectEntity,
        FavoriteTabKind.subjectTopic,
      ]);
      expect(tabs.any((t) => t.kind == FavoriteTabKind.theme), isFalse);
      expect(tabs[0].label, 'Trump');
      expect(tabs[1].label, 'IA santé');
    });

    test('topic not in favorites → excluded', () {
      // Le topic est dans la liste mais PAS dans favorites → ne doit pas apparaître.
      final topics = [
        _topic(
          id: 't1',
          name: 'Technologie raw',
          slugParent: 'tech',
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: const [],
        items: const [],
      );

      expect(tabs, isEmpty);
    });

    test('count = unseen items < 48h matching slug', () {
      final items = [
        _content(id: 'c1', topics: ['ai']),
        _content(id: 'c2', topics: ['ai'], status: ContentStatus.seen),
        _content(
          id: 'c3',
          topics: ['ai'],
          ageBeforeNow: const Duration(hours: 72),
        ),
        _content(id: 'c4', topics: ['climate']),
      ];

      final topics = [
        _topic(
          id: 't1',
          name: 'IA',
          slugParent: 'ai',
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: const [CustomTopicFavoriteRef(id: 't1')],
        items: items,
      );

      final iaTab =
          tabs.firstWhere((t) => t.kind == FavoriteTabKind.subjectTopic);
      expect(iaTab.count, 1);
    });

    test('selected slug marks the matching tab as active', () {
      final topics = [
        _topic(
          id: 't1',
          name: 'IA',
          slugParent: 'ai',
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: const [CustomTopicFavoriteRef(id: 't1')],
        items: const [],
        selectedTopicSlug: 'ai',
      );

      expect(
        tabs.firstWhere((t) => t.slug == 'ai').active,
        isTrue,
      );
    });

    test('source favorite → produces a source tab carrying its Source', () {
      final src = _source(id: 's1', name: 'Le Monde');

      final tabs = buildFavoriteTabModelsForTest(
        topics: const [],
        favorites: const [],
        items: const [],
        sourceFavorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
        sourceById: {'s1': src},
      );

      expect(tabs.map((t) => t.kind).toList(), [
        FavoriteTabKind.source,
      ]);
      final sourceTab =
          tabs.firstWhere((t) => t.kind == FavoriteTabKind.source);
      expect(sourceTab.label, 'Le Monde');
      expect(sourceTab.slug, 's1');
      expect(sourceTab.source, isNotNull);
    });

    test('source favorite absent from catalog → skipped', () {
      final tabs = buildFavoriteTabModelsForTest(
        topics: const [],
        favorites: const [],
        items: const [],
        sourceFavorites: const [
          SourceFavoriteRef(sourceId: 'ghost', position: 0),
        ],
        sourceById: const {},
      );

      expect(tabs, isEmpty);
    });

    test('selectedSourceId marks the matching source tab as active', () {
      final src = _source(id: 's1', name: 'Le Monde');

      final tabs = buildFavoriteTabModelsForTest(
        topics: const [],
        favorites: const [],
        items: const [],
        sourceFavorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
        sourceById: {'s1': src},
        selectedSourceId: 's1',
      );

      expect(
        tabs.firstWhere((t) => t.kind == FavoriteTabKind.source).active,
        isTrue,
      );
    });

    test('unified order interleaves topic and source tabs', () {
      final topics = [_topic(id: 't1', name: 'IA', slugParent: 'ai')];
      final src = _source(id: 's1', name: 'Le Monde');

      // Sans ordre custom : ordre d'insertion = sujets puis sources (plus de
      // tri par count, qui reléguait les sources en fin de liste).
      final defaultTabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: const [CustomTopicFavoriteRef(id: 't1')],
        items: const [],
        sourceFavorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
        sourceById: {'s1': src},
      );
      expect(defaultTabs.map((t) => t.kind).toList(), [
        FavoriteTabKind.subjectTopic,
        FavoriteTabKind.source,
      ]);

      // Avec ordre custom plaçant la source avant le sujet.
      final orderedTabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: const [CustomTopicFavoriteRef(id: 't1')],
        items: const [],
        sourceFavorites: const [SourceFavoriteRef(sourceId: 's1', position: 0)],
        sourceById: {'s1': src},
        order: const ['source:s1', 'topic:t1'],
      );
      expect(orderedTabs.map((t) => t.kind).toList(), [
        FavoriteTabKind.source,
        FavoriteTabKind.subjectTopic,
      ]);
    });

    test('cappe à 10 onglets, en gardant les 10 premiers dans l\'ordre user',
        () {
      final topics = [
        for (var i = 0; i < 6; i++)
          _topic(id: 't$i', name: 'Sujet $i', slugParent: 'p$i'),
      ];
      final favorites = [
        for (var i = 0; i < 6; i++) CustomTopicFavoriteRef(id: 't$i'),
      ];
      final sourceById = {
        for (var i = 0; i < 6; i++)
          's$i': _source(id: 's$i', name: 'Source $i'),
      };
      final sourceFavorites = [
        for (var i = 0; i < 6; i++)
          SourceFavoriteRef(sourceId: 's$i', position: i),
      ];
      // Ordre utilisateur : alterne sujet/source (12 clés).
      final order = <String>[
        for (var i = 0; i < 6; i++) ...['topic:t$i', 'source:s$i'],
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: favorites,
        items: const [],
        sourceFavorites: sourceFavorites,
        sourceById: sourceById,
        order: order,
      );

      // Exactement 10 onglets = les 10 premières clés de `order`.
      expect(tabs, hasLength(10));
      expect(tabs.map((t) => t.label).toList(), const [
        'Sujet 0',
        'Source 0',
        'Sujet 1',
        'Source 1',
        'Sujet 2',
        'Source 2',
        'Sujet 3',
        'Source 3',
        'Sujet 4',
        'Source 4',
      ]);
      // Le surplus (11e/12e clés) est tronqué.
      expect(tabs.any((t) => t.label == 'Sujet 5'), isFalse);
      expect(tabs.any((t) => t.label == 'Source 5'), isFalse);
    });

    test('3 sujets + 3 sources en ordre alterné → les 6 présents, intercalés',
        () {
      final topics = [
        for (var i = 0; i < 3; i++)
          _topic(id: 't$i', name: 'Sujet $i', slugParent: 'p$i'),
      ];
      final favorites = [
        for (var i = 0; i < 3; i++) CustomTopicFavoriteRef(id: 't$i'),
      ];
      final sourceById = {
        for (var i = 0; i < 3; i++)
          's$i': _source(id: 's$i', name: 'Source $i'),
      };
      final sourceFavorites = [
        for (var i = 0; i < 3; i++)
          SourceFavoriteRef(sourceId: 's$i', position: i),
      ];
      final order = const [
        'topic:t0',
        'source:s0',
        'topic:t1',
        'source:s1',
        'topic:t2',
        'source:s2',
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: favorites,
        items: const [],
        sourceFavorites: sourceFavorites,
        sourceById: sourceById,
        order: order,
      );

      expect(tabs, hasLength(6));
      expect(tabs.map((t) => t.label).toList(), const [
        'Sujet 0',
        'Source 0',
        'Sujet 1',
        'Source 1',
        'Sujet 2',
        'Source 2',
      ]);
    });

    test('aucune sélection → aucun onglet actif', () {
      final topics = [_topic(id: 't1', name: 'IA', slugParent: 'ai')];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        favorites: const [CustomTopicFavoriteRef(id: 't1')],
        items: const [],
      );

      expect(tabs.any((t) => t.active), isFalse);
    });
  });

  group('FavoriteTopicTabs widget', () {
    Widget host({
      required Widget child,
      List<UserTopicProfile> topics = const [],
      List<FavoriteRef> favorites = const [],
    }) {
      return ProviderScope(
        overrides: [
          customTopicsProvider.overrideWith(() {
            return _StaticCustomTopicsNotifier(topics);
          }),
          userInterestsProvider.overrideWith(() {
            return _StaticUserInterestsNotifier(favorites);
          }),
        ],
        child: MaterialApp(
          theme: FacteurTheme.lightTheme,
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('tap on active tab calls onTapActiveTab, not onTabTap',
        (tester) async {
      var tapActiveCalls = 0;
      var tabTapCalls = 0;

      await tester.pumpWidget(host(
        topics: [_topic(id: 't1', name: 'IA', slugParent: 'ai')],
        favorites: const [CustomTopicFavoriteRef(id: 't1')],
        child: FavoriteTopicTabs(
          items: const [],
          selectedTopicSlug: 'ai',
          onTabTap: (_, __) => tabTapCalls++,
          onTapActiveTab: () => tapActiveCalls++,
          onAddFavorite: () {},
        ),
      ));
      await tester.pumpAndSettle();

      // L'onglet « IA » est actif (selectedTopicSlug) → tap = onTapActiveTab.
      await tester.tap(find.text('IA'));
      await tester.pump();

      expect(tapActiveCalls, 1);
      expect(tabTapCalls, 0);
    });

    testWidgets('tap on + pill calls onAddFavorite', (tester) async {
      var addCalls = 0;

      await tester.pumpWidget(host(
        child: FavoriteTopicTabs(
          items: const [],
          onTabTap: (_, __) {},
          onTapActiveTab: () {},
          onAddFavorite: () => addCalls++,
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Icon).first);
      await tester.pump();

      expect(addCalls, 1);
    });
  });
}

class _StaticCustomTopicsNotifier extends CustomTopicsNotifier {
  _StaticCustomTopicsNotifier(this._topics);

  final List<UserTopicProfile> _topics;

  @override
  Future<List<UserTopicProfile>> build() async => _topics;
}

class _StaticUserInterestsNotifier extends UserInterestsNotifier {
  _StaticUserInterestsNotifier(this._favorites);

  final List<FavoriteRef> _favorites;

  @override
  Future<UserInterestsState> build() async => UserInterestsState(
        themes: const [],
        customTopics: const [],
        favorites: _favorites,
        favoriteCount: _favorites.length,
        favoriteCap: 5,
      );
}
