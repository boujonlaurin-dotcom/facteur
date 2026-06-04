import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/providers/flaner_discovery_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/feed/widgets/favorite_topic_tabs.dart'
    show FavoriteTabKind;
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockFeedRepository extends Mock implements FeedRepository {}

FeedResponse _resp(List<String> ids) {
  return FeedResponse(
    items: ids
        .map((id) => Content(
              id: id,
              title: 'title-$id',
              url: 'https://x.test/$id',
              contentType: ContentType.article,
              publishedAt: DateTime(2026, 1, 1),
              source: Source(id: 's', name: 'S', type: SourceType.article),
            ))
        .toList(),
    pagination: Pagination(page: 1, perPage: 20, total: 0, hasNext: false),
    carousels: const [],
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _MockFeedRepository feedRepo;

  setUp(() {
    feedRepo = _MockFeedRepository();
  });

  ProviderContainer _container() {
    final container = ProviderContainer(
      overrides: [feedRepositoryProvider.overrideWithValue(feedRepo)],
    );
    addTearDown(container.dispose);
    return container;
  }

  test(
    'subjectTopic → getFeed(topic, includeUnfollowed: true, no followedOnly)',
    () async {
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            topic: any(named: 'topic'),
            theme: any(named: 'theme'),
            entity: any(named: 'entity'),
            includeUnfollowed: any(named: 'includeUnfollowed'),
          )).thenAnswer((_) async => _resp(['a', 'b']));

      final items = await _container().read(
        flanerDiscoveryProvider(
          const FlanerDiscoveryArg(
            kind: FavoriteTabKind.subjectTopic,
            slug: 'startups',
          ),
        ).future,
      );

      expect(items.map((c) => c.id), ['a', 'b']);
      verify(() => feedRepo.getFeed(
            topic: 'startups',
            theme: null,
            entity: null,
            includeUnfollowed: true,
            page: 1,
            limit: 20,
          )).called(1);
    },
  );

  test('theme → getFeed(theme, includeUnfollowed: true)', () async {
    when(() => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          topic: any(named: 'topic'),
          theme: any(named: 'theme'),
          entity: any(named: 'entity'),
          includeUnfollowed: any(named: 'includeUnfollowed'),
        )).thenAnswer((_) async => _resp(['c']));

    await _container().read(
      flanerDiscoveryProvider(
        const FlanerDiscoveryArg(kind: FavoriteTabKind.theme, slug: 'tech'),
      ).future,
    );

    verify(() => feedRepo.getFeed(
          topic: null,
          theme: 'tech',
          entity: null,
          includeUnfollowed: true,
          page: 1,
          limit: 20,
        )).called(1);
  });

  test('subjectEntity → getFeed(entity, includeUnfollowed: true)', () async {
    when(() => feedRepo.getFeed(
          page: any(named: 'page'),
          limit: any(named: 'limit'),
          topic: any(named: 'topic'),
          theme: any(named: 'theme'),
          entity: any(named: 'entity'),
          includeUnfollowed: any(named: 'includeUnfollowed'),
        )).thenAnswer((_) async => _resp(['d']));

    await _container().read(
      flanerDiscoveryProvider(
        const FlanerDiscoveryArg(
          kind: FavoriteTabKind.subjectEntity,
          slug: 'OpenAI',
        ),
      ).future,
    );

    verify(() => feedRepo.getFeed(
          topic: null,
          theme: null,
          entity: 'OpenAI',
          includeUnfollowed: true,
          page: 1,
          limit: 20,
        )).called(1);
  });

  test('FlanerDiscoveryArg equality keys the family cache', () {
    const a = FlanerDiscoveryArg(
      kind: FavoriteTabKind.subjectTopic,
      slug: 'startups',
    );
    const b = FlanerDiscoveryArg(
      kind: FavoriteTabKind.subjectTopic,
      slug: 'startups',
    );
    const c = FlanerDiscoveryArg(
      kind: FavoriteTabKind.theme,
      slug: 'startups',
    );
    expect(a, equals(b));
    expect(a.hashCode, equals(b.hashCode));
    expect(a, isNot(equals(c)));
  });
}
