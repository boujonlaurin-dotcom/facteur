import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:facteur/config/theme.dart';
import 'package:facteur/features/custom_topics/models/topic_models.dart';
import 'package:facteur/features/custom_topics/providers/custom_topics_provider.dart';
import 'package:facteur/features/custom_topics/providers/theme_priority_provider.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/widgets/favorite_topic_tabs.dart';
import 'package:facteur/features/sources/models/source_model.dart';

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
    test('0 favoris → only "Tous" tab', () {
      final tabs = buildFavoriteTabModelsForTest(
        topics: const [],
        themePriority: const {},
        items: const [],
      );

      expect(tabs, hasLength(1));
      expect(tabs.first.kind, FavoriteTabKind.tous);
      expect(tabs.first.label, 'Tous');
      expect(tabs.first.active, isTrue);
    });

    test('2 sujets + 1 thème → 4 tabs in order subjects → themes', () {
      final topics = [
        _topic(
          id: 't1',
          name: 'IA santé',
          slugParent: 'ai-health',
          priorityMultiplier: 2.0,
        ),
        _topic(
          id: 't2',
          name: 'Trump',
          entityType: 'PERSON',
          canonicalName: 'Donald Trump',
          priorityMultiplier: 2.0,
          compositeScore: 0.8,
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        themePriority: const {'Environnement': 2.0},
        items: const [],
      );

      expect(tabs.map((t) => t.kind).toList(), [
        FavoriteTabKind.tous,
        FavoriteTabKind.subjectEntity,
        FavoriteTabKind.subjectTopic,
        FavoriteTabKind.theme,
      ]);
      expect(tabs[1].label, 'Trump');
      expect(tabs[2].label, 'IA santé');
      expect(tabs[3].label, 'Environnement');
      expect(tabs[3].slug, 'environment');
      expect(tabs[3].emoji, isNotEmpty);
    });

    test('topics whose slugParent is a macro-theme slug are excluded', () {
      // slugParent == "tech" matches the Technologie macro-theme apiSlug.
      final topics = [
        _topic(
          id: 't1',
          name: 'Technologie raw',
          slugParent: 'tech',
          priorityMultiplier: 2.0,
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        themePriority: const {},
        items: const [],
      );

      // Only "Tous" should appear — the topic was filtered out.
      expect(tabs, hasLength(1));
      expect(tabs.first.kind, FavoriteTabKind.tous);
    });

    test('count = unseen items < 48h matching slug', () {
      final items = [
        // Match topic "ai", recent + unseen → counted
        _content(id: 'c1', topics: ['ai']),
        // Match topic "ai", recent but seen → NOT counted
        _content(id: 'c2', topics: ['ai'], status: ContentStatus.seen),
        // Match topic "ai", unseen but too old → NOT counted
        _content(
          id: 'c3',
          topics: ['ai'],
          ageBeforeNow: const Duration(hours: 72),
        ),
        // Wrong topic → NOT counted
        _content(id: 'c4', topics: ['climate']),
      ];

      final topics = [
        _topic(
          id: 't1',
          name: 'IA',
          slugParent: 'ai',
          priorityMultiplier: 2.0,
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        themePriority: const {},
        items: items,
      );

      final iaTab =
          tabs.firstWhere((t) => t.kind == FavoriteTabKind.subjectTopic);
      expect(iaTab.count, 1);

      final tousTab =
          tabs.firstWhere((t) => t.kind == FavoriteTabKind.tous);
      // Tous = unseen + recent: c1 + c4 = 2.
      expect(tousTab.count, 2);
    });

    test('selected slug marks the matching tab as active', () {
      final topics = [
        _topic(
          id: 't1',
          name: 'IA',
          slugParent: 'ai',
          priorityMultiplier: 2.0,
        ),
      ];

      final tabs = buildFavoriteTabModelsForTest(
        topics: topics,
        themePriority: const {},
        items: const [],
        selectedTopicSlug: 'ai',
      );

      expect(
        tabs.firstWhere((t) => t.slug == 'ai').active,
        isTrue,
      );
      expect(
        tabs.firstWhere((t) => t.kind == FavoriteTabKind.tous).active,
        isFalse,
      );
    });
  });

  group('FavoriteTopicTabs widget', () {
    Widget host({
      required Widget child,
      List<UserTopicProfile> topics = const [],
      Map<String, double> themePriority = const {},
    }) {
      return ProviderScope(
        overrides: [
          customTopicsProvider.overrideWith(() {
            return _StaticCustomTopicsNotifier(topics);
          }),
          themePriorityProvider.overrideWith((ref) async => themePriority),
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
        child: FavoriteTopicTabs(
          items: const [],
          onTabTap: (_, __) => tabTapCalls++,
          onTapActiveTab: () => tapActiveCalls++,
          onAddFavorite: () {},
        ),
      ));
      // Let async providers resolve.
      await tester.pumpAndSettle();

      // "Tous" is the active tab when no selection is set.
      await tester.tap(find.text('Tous'));
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

      // The + pill is the only icon in the row.
      await tester.tap(find.byType(Icon).first);
      await tester.pump();

      expect(addCalls, 1);
    });
  });
}

/// Test-only notifier that returns a static list and skips network/cache.
class _StaticCustomTopicsNotifier extends CustomTopicsNotifier {
  _StaticCustomTopicsNotifier(this._topics);

  final List<UserTopicProfile> _topics;

  @override
  Future<List<UserTopicProfile>> build() async => _topics;
}
