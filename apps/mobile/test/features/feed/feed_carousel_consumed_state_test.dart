import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/widgets/reading_badge.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Verifies the state-update logic used by markContentAsConsumed/updateContent
/// for carousel items. We test the pure list transformation since instantiating
/// FeedNotifier requires a full Riverpod + auth setup.
void main() {
  Source mkSource() => Source(
        id: 's1',
        name: 'Source',
        url: 'https://example.com',
        type: SourceType.article,
      );

  Content mkContent(String id, ContentStatus status) => Content(
        id: id,
        title: 'T',
        url: 'https://example.com/$id',
        contentType: ContentType.article,
        publishedAt: DateTime.now(),
        source: mkSource(),
        status: status,
      );

  /// Mirrors `_updateCarouselItem` from feed_provider.dart.
  List<FeedCarouselData> updateCarouselItem(
    List<FeedCarouselData> carousels,
    String contentId,
    Content Function(Content) updater,
  ) {
    return carousels.map((carousel) {
      final hasItem = carousel.items.any((item) => item.id == contentId);
      if (!hasItem) return carousel;
      final updatedItems = carousel.items.map((item) {
        if (item.id == contentId) return updater(item);
        return item;
      }).toList();
      return carousel.copyWith(items: updatedItems);
    }).toList();
  }

  test('updateCarouselItem flips a single item status to consumed', () {
    final carousel = FeedCarouselData(
      carouselType: 'related',
      title: 'Related',
      emoji: '🧵',
      position: 5,
      items: [
        mkContent('a', ContentStatus.unseen),
        mkContent('b', ContentStatus.unseen),
      ],
      badges: const [],
    );

    final updated = updateCarouselItem(
      [carousel],
      'a',
      (c) => c.copyWith(status: ContentStatus.consumed),
    );

    expect(updated[0].items[0].status, ContentStatus.consumed);
    expect(updated[0].items[1].status, ContentStatus.unseen);
    // Ensure new instances (Riverpod compares by reference for state changes).
    expect(identical(updated[0], carousel), isFalse);
    expect(identical(updated[0].items[0], carousel.items[0]), isFalse);
  });

  test('updateCarouselItem leaves carousels without the item untouched', () {
    final c1 = FeedCarouselData(
      carouselType: 'a',
      title: 'A',
      emoji: '',
      position: 5,
      items: [mkContent('x', ContentStatus.unseen)],
      badges: const [],
    );
    final c2 = FeedCarouselData(
      carouselType: 'b',
      title: 'B',
      emoji: '',
      position: 10,
      items: [mkContent('y', ContentStatus.unseen)],
      badges: const [],
    );

    final updated = updateCarouselItem(
      [c1, c2],
      'y',
      (c) => c.copyWith(status: ContentStatus.consumed),
    );

    expect(identical(updated[0], c1), isTrue);
    expect(updated[1].items[0].status, ContentStatus.consumed);
  });

  testWidgets('ReadingBadge renders "Lu" with green check for consumed status',
      (tester) async {
    final consumed = mkContent('a', ContentStatus.consumed);
    await tester.pumpWidget(
      MaterialApp(
        theme: FacteurTheme.lightTheme,
        home: Scaffold(body: ReadingBadge(content: consumed)),
      ),
    );
    expect(find.text('Lu'), findsOneWidget);
  });

  test('silent revalidation merge preserves consumed status from current state',
      () {
    // Simulate the race: current state has item 'a' consumed (optimistic
    // update), fresh API response has item 'a' with unseen (stale server cache).
    final currentCarousels = [
      FeedCarouselData(
        carouselType: 'related',
        title: 'Related',
        emoji: '',
        position: 5,
        items: [
          mkContent('a', ContentStatus.consumed),
          mkContent('b', ContentStatus.unseen),
        ],
        badges: const [],
      )
    ];
    final freshCarousels = [
      FeedCarouselData(
        carouselType: 'related',
        title: 'Related',
        emoji: '',
        position: 5,
        items: [
          mkContent('a', ContentStatus.unseen), // stale API response
          mkContent('b', ContentStatus.unseen),
        ],
        badges: const [],
      )
    ];

    // Mirror the merge logic from _scheduleSilentRevalidation.
    final consumedIds = <String>{
      ...currentCarousels.expand((carousel) => carousel.items
          .where((c) => c.status == ContentStatus.consumed)
          .map((c) => c.id)),
    };
    Content preserve(Content c) => consumedIds.contains(c.id)
        ? c.copyWith(status: ContentStatus.consumed)
        : c;
    final merged = freshCarousels
        .map((car) => car.copyWith(items: car.items.map(preserve).toList()))
        .toList();

    expect(merged[0].items[0].status, ContentStatus.consumed,
        reason: 'consumed status must survive silent revalidation overwrite');
    expect(merged[0].items[1].status, ContentStatus.unseen);
  });

  test('readCount logic counts consumed AND progress>0 items', () {
    final items = [
      mkContent('a', ContentStatus.consumed),
      mkContent('b', ContentStatus.unseen).copyWith(readingProgress: 50),
      mkContent('c', ContentStatus.unseen),
    ];

    final readCount = items
        .where((c) =>
            c.status == ContentStatus.consumed || c.readingProgress > 0)
        .length;

    expect(readCount, 2);
  });
}
