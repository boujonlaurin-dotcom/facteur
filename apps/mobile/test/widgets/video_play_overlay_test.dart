import 'package:facteur/widgets/design/video_play_overlay.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

void main() {
  Widget createWidget(Widget child) {
    return MaterialApp(
      home: Scaffold(
        body: Center(child: child),
      ),
    );
  }

  group('VideoPlayOverlay', () {
    testWidgets('renders without error', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(const VideoPlayOverlay()));

      expect(find.byType(VideoPlayOverlay), findsOneWidget);
    });

    testWidgets('contains a play icon', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(const VideoPlayOverlay()));

      // Find the Icon widget with PhosphorIcons play
      expect(find.byType(Icon), findsOneWidget);

      final icon = tester.widget<Icon>(find.byType(Icon));
      expect(icon.icon, equals(PhosphorIcons.play(PhosphorIconsStyle.fill)));
      expect(icon.size, equals(24));
      expect(icon.color, equals(Colors.black87));
    });

    testWidgets('has a white circle container', (WidgetTester tester) async {
      await tester.pumpWidget(createWidget(const VideoPlayOverlay()));

      final container = tester.widget<Container>(find.byType(Container).first);
      expect(container.constraints?.maxWidth, equals(52));
      expect(container.constraints?.maxHeight, equals(52));

      final decoration = container.decoration as BoxDecoration;
      expect(decoration.shape, equals(BoxShape.circle));
      // White with alpha ~0.85
      expect(decoration.color, isNotNull);
      expect(decoration.color!.red, equals(255));
      expect(decoration.color!.green, equals(255));
      expect(decoration.color!.blue, equals(255));
    });
  });
}
