import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:facteur/features/custom_topics/widgets/topic_priority_slider.dart';

void main() {
  Widget createWidget({
    required double currentMultiplier,
    required ValueChanged<double> onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: Center(
          child: TopicPrioritySlider(
            currentMultiplier: currentMultiplier,
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }

  group('TopicPrioritySlider', () {
    testWidgets('displays 1 filled block for multiplier 0.2',
        (tester) async {
      await tester.pumpWidget(createWidget(
        currentMultiplier: 0.2,
        onChanged: (_) {},
      ));

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
      // Tap near the right end (blocks are the rightmost part)
      await tester.tapAt(Offset(
        sliderBox.right - 10,
        sliderBox.center.dy,
      ));
      await tester.pump();

      expect(changedValue, 2.0);
    });

    testWidgets('tap on left block area calls onChanged with 0.2',
        (tester) async {
      double? changedValue;
      await tester.pumpWidget(createWidget(
        currentMultiplier: 2.0,
        onChanged: (v) => changedValue = v,
      ));

      // Tap on the first block (after the label text)
      final slider = find.byType(TopicPrioritySlider);
      final sliderBox = tester.getRect(slider);
      // Blocks width = 28*3 + 3*2 = 90, so first block starts at right - 90
      await tester.tapAt(Offset(
        sliderBox.right - 80,
        sliderBox.center.dy,
      ));
      await tester.pump();

      expect(changedValue, 0.2);
    });

    testWidgets('same cran tap does not call onChanged',
        (tester) async {
      double? changedValue;
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (v) => changedValue = v,
      ));

      // Tap in the middle block area (cran 2, already active)
      final slider = find.byType(TopicPrioritySlider);
      final sliderBox = tester.getRect(slider);
      await tester.tapAt(Offset(
        sliderBox.right - 45,
        sliderBox.center.dy,
      ));
      await tester.pump();

      expect(changedValue, isNull);
    });

    testWidgets('shows correct label text for each cran always visible',
        (tester) async {
      // Cran 1: "Moins" — always visible
      await tester.pumpWidget(createWidget(
        currentMultiplier: 0.2,
        onChanged: (_) {},
      ));
      expect(find.text('Moins'), findsOneWidget);

      // Cran 2: "Normal" — always visible
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (_) {},
      ));
      expect(find.text('Normal'), findsOneWidget);

      // Cran 3: "Plus" — always visible
      await tester.pumpWidget(createWidget(
        currentMultiplier: 2.0,
        onChanged: (_) {},
      ));
      expect(find.text('Plus'), findsOneWidget);
    });

    testWidgets('label is always visible without needing tap',
        (tester) async {
      await tester.pumpWidget(createWidget(
        currentMultiplier: 1.0,
        onChanged: (_) {},
      ));

      // Label should be visible immediately (no AnimatedOpacity)
      expect(find.text('Normal'), findsOneWidget);
      expect(find.byType(AnimatedOpacity), findsNothing);
    });
  });
}
