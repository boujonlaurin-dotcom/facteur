import 'package:facteur/config/theme.dart';
import 'package:facteur/features/feed/models/content_model.dart';
import 'package:facteur/features/feed/widgets/feed_card.dart';
import 'package:facteur/features/sources/models/source_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

Content _content(String id) => Content(
      id: id,
      title: id,
      url: 'https://x.test/$id',
      contentType: ContentType.article,
      publishedAt: DateTime(2026, 6, 19),
      source: Source(id: 's', name: 'Source', type: SourceType.article),
    );

/// Reproduit le contexte carrousel : une `PageView` (viewportFraction 0.88)
/// dont la physique de drag horizontal entre en concurrence dans l'arène avec
/// le long-press de la `FeedCard`.
Widget _carousel({
  required void Function() onTap,
  required void Function() onLongPressStart,
  required void Function() onMoveUpdate,
}) {
  return MaterialApp(
    theme: ThemeData(extensions: [FacteurPalettes.light]),
    home: Scaffold(
      body: Center(
        child: SizedBox(
          height: 360,
          child: PageView(
            controller: PageController(viewportFraction: 0.88),
            children: [
              for (var i = 0; i < 3; i++)
                FeedCard(
                  content: _content('Page $i'),
                  onTap: i == 0 ? onTap : null,
                  onLongPressStart:
                      i == 0 ? (_) => onLongPressStart() : null,
                  onLongPressMoveUpdate: i == 0 ? (_) => onMoveUpdate() : null,
                  onLongPressEnd: i == 0 ? (_) {} : null,
                ),
            ],
          ),
        ),
      ),
    ),
  );
}

void main() {
  setUpAll(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  // tap/long-press handlers `await HapticFeedback.mediumImpact()` avant le
  // callback : sans handler de canal, ce Future ne se résout jamais en test et
  // le callback ne part pas. On mocke le canal pour qu'il complète.
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  group('FeedCard long-press in a carousel', () {
    testWidgets(
        'wins the arena with a slight horizontal drift before the deadline',
        (tester) async {
      var longPressStarted = false;
      var moveUpdates = 0;
      await tester.pumpWidget(_carousel(
        onTap: () {},
        onLongPressStart: () => longPressStarted = true,
        onMoveUpdate: () => moveUpdates++,
      ));

      final gesture =
          await tester.startGesture(tester.getCenter(find.text('Page 0')));
      await tester.pump(const Duration(milliseconds: 100));
      // Dérive < kTouchSlop (18 px) : la PageView ne réclame pas le geste.
      await gesture.moveBy(const Offset(8, 0));
      // Franchit la deadline raccourcie (300 ms) → le long-press l'emporte.
      await tester.pump(const Duration(milliseconds: 260));

      expect(longPressStarted, isTrue,
          reason: 'Le long-press doit gagner malgré la légère dérive.');

      await gesture.moveBy(const Offset(0, 24));
      await tester.pump();
      expect(moveUpdates, greaterThan(0),
          reason: 'Le scroll de l’aperçu suit le doigt après le déclenchement.');

      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a quick horizontal fling pages instead of triggering preview',
        (tester) async {
      var longPressStarted = false;
      await tester.pumpWidget(_carousel(
        onTap: () {},
        onLongPressStart: () => longPressStarted = true,
        onMoveUpdate: () {},
      ));

      // Fling rapide : relâché bien avant la deadline 300 ms → pas de long-press.
      await tester.fling(
        find.text('Page 0'),
        const Offset(-300, 0),
        1000,
      );
      await tester.pumpAndSettle();

      expect(longPressStarted, isFalse);
    });

    testWidgets('a short tap fires onTap', (tester) async {
      var tapped = false;
      await tester.pumpWidget(_carousel(
        onTap: () => tapped = true,
        onLongPressStart: () {},
        onMoveUpdate: () {},
      ));

      await tester.tap(find.text('Page 0'));
      await tester.pumpAndSettle();

      expect(tapped, isTrue);
    });
  });
}
