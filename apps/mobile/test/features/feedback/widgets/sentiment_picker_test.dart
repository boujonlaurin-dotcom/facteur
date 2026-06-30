import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mocktail/mocktail.dart';
import 'package:facteur/features/feedback/providers/feedback_providers.dart';
import 'package:facteur/features/feedback/repositories/feedback_repository.dart';
import 'package:facteur/features/feedback/widgets/sentiment_picker.dart';

class MockFeedbackRepository extends Mock implements FeedbackRepository {}

void main() {
  late MockFeedbackRepository mockRepo;

  setUpAll(() {
    registerFallbackValue(DateTime(2024, 1, 1));
  });

  setUp(() {
    mockRepo = MockFeedbackRepository();
    when(() => mockRepo.submitSentiment(any(), date: any(named: 'date')))
        .thenAnswer((_) async {});
  });

  Widget createWidget() {
    return ProviderScope(
      overrides: [
        feedbackRepositoryProvider.overrideWithValue(mockRepo),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: Center(child: SentimentPicker()),
        ),
      ),
    );
  }

  group('SentimentPicker', () {
    testWidgets('renders the question and three emojis', (tester) async {
      await tester.pumpWidget(createWidget());

      expect(find.textContaining('c\'était comment'), findsOneWidget);
      expect(find.text('😴'), findsOneWidget);
      expect(find.text('🙂'), findsOneWidget);
      expect(find.text('🔥'), findsOneWidget);
    });

    testWidgets('tapping an emoji submits sentiment and shows thanks',
        (tester) async {
      await tester.pumpWidget(createWidget());

      await tester.tap(find.text('🔥'));
      await tester.pump();

      verify(() => mockRepo.submitSentiment('high', date: any(named: 'date')))
          .called(1);
      expect(find.textContaining('Merci'), findsOneWidget);
      // Emojis are gone after selection
      expect(find.text('🔥'), findsNothing);
    });

    testWidgets('only submits once even on repeated taps', (tester) async {
      await tester.pumpWidget(createWidget());

      await tester.tap(find.text('🙂'));
      await tester.pump();
      // After first tap the picker is replaced by the thanks message, so a
      // second tap on the (now absent) emoji is a no-op.
      verify(() => mockRepo.submitSentiment('ok', date: any(named: 'date')))
          .called(1);
    });
  });
}
