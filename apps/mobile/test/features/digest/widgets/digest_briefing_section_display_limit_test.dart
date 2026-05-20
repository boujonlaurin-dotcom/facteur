import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/digest/models/digest_models.dart';
import 'package:facteur/features/digest/widgets/digest_briefing_section.dart';
import 'package:facteur/features/digest/widgets/topic_section.dart';

DigestItem _item(String id) => DigestItem(
      contentId: id,
      title: 'Article $id',
      url: 'https://example.com/$id',
      source: const SourceMini(id: 'src-1', name: 'Source 1'),
    );

DigestTopic _topic(int rank) => DigestTopic(
      topicId: 'topic-$rank',
      label: 'Sujet $rank',
      rank: rank,
      articles: [_item('content-$rank-a')],
    );

void main() {
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  Widget buildWidget({
    required List<DigestTopic> topics,
    required int displayLimit,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: DigestBriefingSection(
            items: const [],
            topics: topics,
            displayLimit: displayLimit,
            onItemTap: (_) {},
          ),
        ),
      ),
    );
  }

  group('DigestBriefingSection.displayLimit (topics layout)', () {
    testWidgets('renders only displayLimit topics and a "Voir N autres" CTA',
        (tester) async {
      final topics = List.generate(10, (i) => _topic(i + 1));

      await tester.pumpWidget(buildWidget(topics: topics, displayLimit: 3));
      await tester.pump();

      // 3 sujets rendus, pas 10.
      expect(find.byType(TopicSection), findsNWidgets(3));

      // Le bouton est bien rendu (hidden = 10 - 3 = 7).
      expect(find.byKey(const ValueKey('digest_show_more_toggle')),
          findsOneWidget);
      expect(find.text('Voir 7 autres articles'), findsOneWidget);
    });

    testWidgets('tapping CTA reveals all topics and flips label to "Réduire"',
        (tester) async {
      final topics = List.generate(10, (i) => _topic(i + 1));

      await tester.pumpWidget(buildWidget(topics: topics, displayLimit: 3));
      await tester.pump();
      expect(find.byType(TopicSection), findsNWidgets(3));

      await tester.tap(find.byKey(const ValueKey('digest_show_more_toggle')));
      await tester.pump();

      // Tous les topics maintenant rendus.
      expect(find.byType(TopicSection), findsNWidgets(10));

      // Le label a basculé sur "Réduire".
      expect(find.text('Réduire'), findsOneWidget);
      expect(find.text('Voir 7 autres articles'), findsNothing);
    });

    testWidgets('hides CTA entirely when topics.length <= displayLimit',
        (tester) async {
      final topics = List.generate(3, (i) => _topic(i + 1));

      await tester.pumpWidget(buildWidget(topics: topics, displayLimit: 5));
      await tester.pump();

      expect(find.byType(TopicSection), findsNWidgets(3));
      expect(find.byKey(const ValueKey('digest_show_more_toggle')),
          findsNothing);
    });

    testWidgets('falls back to "Voir 1 autre article" when only 1 hidden',
        (tester) async {
      final topics = List.generate(4, (i) => _topic(i + 1));

      await tester.pumpWidget(buildWidget(topics: topics, displayLimit: 3));
      await tester.pump();

      expect(find.text('Voir 1 autre article'), findsOneWidget);
    });

    testWidgets('displayLimit=null disables slicing (legacy behavior)',
        (tester) async {
      final topics = List.generate(10, (i) => _topic(i + 1));

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: DigestBriefingSection(
                items: const [],
                topics: topics,
                onItemTap: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Sans displayLimit, tous les topics sont rendus, pas de toggle.
      expect(find.byType(TopicSection), findsNWidgets(10));
      expect(find.byKey(const ValueKey('digest_show_more_toggle')),
          findsNothing);
    });
  });
}
