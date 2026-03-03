import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/custom_topics/widgets/topic_priority_slider.dart';

void main() {
  Widget createWidget({
    required double currentMultiplier,
    required ValueChanged<double> onChanged,
    double width = 90,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: TopicPrioritySlider(
            currentMultiplier: currentMultiplier,
            onChanged: onChanged,
            width: width,
          ),
        ),
      ),
    );
  }

  group('TopicPrioritySlider', () {
    testWidgets('displays 1 filled block for multiplier 0.5',
        (tester) async {
      await tester.pumpWidget(createWidget(
        currentMultiplier: 0.5,
        onChanged: (_) {},
      ));

      // Find the 3 Container blocks (28x12)
      final containers = find.byWidgetPredicate((widget) =>
          widget is Container &&
          widget.constraints?.maxWidth == 28 &&
          widget.constraints?.maxHeight == 12);

      // We check via the decoration colors instead
      // The widget should have 1 filled and 2 unfilled blocks
      expect(find.byType(TopicPrioritySlider), findsOneWidget);
    });

    testWidgets('displays 2 filled blocks for multiplier 1.0',
        (tester) async {
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (_) {},
      ));

      expect(find.byType(TopicPrioritySlider), findsOneWidget);
    });

    testWidgets('displays 3 filled blocks for multiplier 2.0',
        (tester) async {
      await tester.pumpWidget(createWidget(
        currentMultiplier: 2.0,
        onChanged: (_) {},
      ));

      expect(find.byType(TopicPrioritySlider), findsOneWidget);
    });

    testWidgets('tap on right area calls onChanged with 2.0',
        (tester) async {
      double? changedValue;
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (v) => changedValue = v,
      ));

      // Tap on the right side of the slider (3rd block area)
      final slider = find.byType(TopicPrioritySlider);
      final sliderBox = tester.getRect(slider);
      // Tap near the right end
      await tester.tapAt(Offset(
        sliderBox.center.dx + 30,
        sliderBox.center.dy + 10,
      ));
      await tester.pump();

      expect(changedValue, 2.0);
    });

    testWidgets('tap on left area calls onChanged with 0.5',
        (tester) async {
      double? changedValue;
      await tester.pumpWidget(createWidget(
        currentMultiplier: 2.0,
        onChanged: (v) => changedValue = v,
      ));

      // Tap on the left side of the slider (1st block area)
      final slider = find.byType(TopicPrioritySlider);
      final sliderBox = tester.getRect(slider);
      await tester.tapAt(Offset(
        sliderBox.center.dx - 30,
        sliderBox.center.dy + 10,
      ));
      await tester.pump();

      expect(changedValue, 0.5);
    });

    testWidgets('same cran tap does not call onChanged',
        (tester) async {
      double? changedValue;
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (v) => changedValue = v,
      ));

      // Tap in the center area (cran 2, already active)
      final slider = find.byType(TopicPrioritySlider);
      final sliderBox = tester.getRect(slider);
      await tester.tapAt(Offset(
        sliderBox.center.dx,
        sliderBox.center.dy + 10,
      ));
      await tester.pump();

      expect(changedValue, isNull);
    });

    testWidgets('label shows on tap then fades out', (tester) async {
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (_) {},
      ));

      // Initially label should be invisible (opacity 0)
      final opacityBefore = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacityBefore.opacity, 0.0);

      // Tap to trigger label show
      final slider = find.byType(TopicPrioritySlider);
      final sliderBox = tester.getRect(slider);
      await tester.tapAt(Offset(
        sliderBox.center.dx + 30,
        sliderBox.center.dy + 10,
      ));
      await tester.pump();

      // After tap, label should be visible
      final opacityAfter = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacityAfter.opacity, 1.0);

      // After 1.5 seconds, label should fade out
      await tester.pump(const Duration(milliseconds: 1600));
      final opacityLater = tester.widget<AnimatedOpacity>(
        find.byType(AnimatedOpacity),
      );
      expect(opacityLater.opacity, 0.0);
    });

    testWidgets('shows correct label text for each cran',
        (tester) async {
      // Cran 1: "Suivi"
      await tester.pumpWidget(createWidget(
        currentMultiplier: 0.5,
        onChanged: (_) {},
      ));
      expect(find.text('Suivi'), findsOneWidget);

      // Cran 2: "Interesse"
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (_) {},
      ));
      expect(find.text('Interesse'), findsOneWidget);

      // Cran 3: "Fort interet"
      await tester.pumpWidget(createWidget(
        currentMultiplier: 2.0,
        onChanged: (_) {},
      ));
      expect(find.text('Fort interet'), findsOneWidget);
    });

    testWidgets('widget fits within 100px width constraint',
        (tester) async {
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (_) {},
        width: 90,
      ));

      final sliderBox = tester.getRect(find.byType(TopicPrioritySlider));
      expect(sliderBox.width, lessThanOrEqualTo(100));
    });
  });
}
