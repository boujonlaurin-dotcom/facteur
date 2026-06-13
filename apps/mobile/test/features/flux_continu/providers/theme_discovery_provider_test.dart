import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/providers/feed_provider.dart';
import 'package:facteur/features/feed/repositories/feed_repository.dart';
import 'package:facteur/features/flux_continu/providers/theme_discovery_provider.dart';
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

  test(
    'themeDiscoveryProvider calls getFeed(theme, includeUnfollowed: true, limit: 20)',
    () async {
      when(() => feedRepo.getFeed(
            page: any(named: 'page'),
            limit: any(named: 'limit'),
            theme: any(named: 'theme'),
            includeUnfollowed: any(named: 'includeUnfollowed'),
          )).thenAnswer((_) async => _resp(['a', 'b']));

      final container = ProviderContainer(
        overrides: [
          feedRepositoryProvider.overrideWithValue(feedRepo),
        ],
      );
      addTearDown(container.dispose);

      final items = await container.read(
        themeDiscoveryProvider('tech').future,
      );

      expect(items.map((c) => c.id), ['a', 'b']);
      verify(() => feedRepo.getFeed(
            theme: 'tech',
            includeUnfollowed: true,
            page: 1,
            limit: 20,
          )).called(1);
    },
  );
}
